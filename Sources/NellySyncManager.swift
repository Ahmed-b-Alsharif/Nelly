import Foundation
import SwiftUI
import Security

@MainActor
final class NellySyncManager: ObservableObject {
    // Set this to the deployed Nelly Worker URL after the free Cloudflare
    // D1 database and R2 bucket have been created.
    private let serviceURL = "https://REPLACE-WITH-NELLY-WORKER.workers.dev"
    private let keychainService = "com.ahmedalsharif.nelly.sync"

    @Published private(set) var familyID: String?
    @Published private(set) var deviceName: String?
    @Published private(set) var pairingCode: String?
    @Published private(set) var pairingCodeExpiry: Date?
    @Published private(set) var statusMessage = "Not connected"
    @Published private(set) var isBusy = false

    private var deviceToken: String?

    var isConfigured: Bool {
        !serviceURL.contains("REPLACE-WITH")
    }

    var isPaired: Bool {
        familyID != nil && deviceToken != nil
    }

    init() {
        familyID = UserDefaults.standard.string(forKey: "nelly.sync.familyID")
        deviceName = UserDefaults.standard.string(forKey: "nelly.sync.deviceName")
        deviceToken = readKeychainToken()
        if familyID != nil && deviceToken != nil {
            statusMessage = "This iPhone is paired"
        } else {
            familyID = nil
            deviceToken = nil
        }
    }

    func createFamily(deviceName: String) async {
        guard isConfigured else {
            statusMessage = "The free sync server must be deployed before pairing."
            return
        }
        await performRequest(path: "/v1/families", body: ["deviceName": deviceName]) { [weak self] data in
            guard let self,
                  let response = try? JSONDecoder().decode(CreateFamilyResponse.self, from: data) else {
                self?.statusMessage = "The server returned an invalid response."
                return
            }
            do {
                try self.saveToken(response.deviceToken)
                self.familyID = response.familyId
                self.deviceName = deviceName
                self.pairingCode = response.pairingCode
                self.pairingCodeExpiry = Date(timeIntervalSince1970: TimeInterval(response.pairingCodeExpiresAt))
                UserDefaults.standard.set(response.familyId, forKey: "nelly.sync.familyID")
                UserDefaults.standard.set(deviceName, forKey: "nelly.sync.deviceName")
                self.statusMessage = "Family created. Enter this code on the second iPhone."
            } catch {
                self.statusMessage = "Could not securely save the pairing key. Please try again."
            }
        }
    }

    func joinFamily(pairingCode: String, deviceName: String) async {
        guard isConfigured else {
            statusMessage = "The free sync server must be deployed before pairing."
            return
        }
        await performRequest(path: "/v1/pair", body: [
            "pairingCode": pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            "deviceName": deviceName
        ]) { [weak self] data in
            guard let self,
                  let response = try? JSONDecoder().decode(PairFamilyResponse.self, from: data) else {
                self?.statusMessage = "Pairing failed. Check the code and try again."
                return
            }
            do {
                try self.saveToken(response.deviceToken)
                self.familyID = response.familyId
                self.deviceName = deviceName
                self.pairingCode = nil
                self.pairingCodeExpiry = nil
                UserDefaults.standard.set(response.familyId, forKey: "nelly.sync.familyID")
                UserDefaults.standard.set(deviceName, forKey: "nelly.sync.deviceName")
                self.statusMessage = "This iPhone is paired successfully."
            } catch {
                self.statusMessage = "Could not securely save the pairing key. Please try again."
            }
        }
    }

    func disconnect() {
        deleteKeychainToken()
        deviceToken = nil
        familyID = nil
        deviceName = nil
        pairingCode = nil
        pairingCodeExpiry = nil
        UserDefaults.standard.removeObject(forKey: "nelly.sync.familyID")
        UserDefaults.standard.removeObject(forKey: "nelly.sync.deviceName")
        statusMessage = "Disconnected on this iPhone. The other iPhone is not changed."
    }

    private func performRequest(
        path: String,
        body: [String: String],
        completion: @escaping (Data) -> Void
    ) async {
        guard let base = URL(string: serviceURL),
              let url = URL(string: path, relativeTo: base) else {
            statusMessage = "The sync server address is not configured."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                statusMessage = "Could not connect or the pairing code was rejected."
                return
            }
            completion(data)
        } catch {
            statusMessage = "Could not reach the sync server. Check the internet connection."
        }
    }

    private func saveToken(_ token: String) throws {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "device-token",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.saveFailed }
        deviceToken = token
    }

    private func readKeychainToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "device-token",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeychainToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "device-token"
        ]
        SecItemDelete(query as CFDictionary)
    }

    private struct CreateFamilyResponse: Decodable {
        let familyId: String
        let deviceToken: String
        let pairingCode: String
        let pairingCodeExpiresAt: Int
    }

    private struct PairFamilyResponse: Decodable {
        let familyId: String
        let deviceToken: String
    }

    private enum KeychainError: Error {
        case saveFailed
    }
}
