import Foundation
import SwiftUI
import Security

@MainActor
final class NellySyncManager: ObservableObject {
    // Replace this with the deployed Worker URL after Cloudflare's Git deployment.
    private let serviceURL = "https://REPLACE-WITH-NELLY-WORKER.workers.dev"
    private let keychainService = "com.ahmedalsharif.nelly.sync"
    private let chunkBytes = 4 * 1024 * 1024
    private let maxVideoBytes = 100 * 1024 * 1024

    @Published private(set) var familyID: String?
    @Published private(set) var deviceName: String?
    @Published private(set) var pairingCode: String?
    @Published private(set) var pairingCodeExpiry: Date?
    @Published private(set) var statusMessage = "Not connected"
    @Published private(set) var isBusy = false
    @Published private(set) var lastSyncDate: Date?

    private var deviceToken: String?

    var isConfigured: Bool { !serviceURL.contains("REPLACE-WITH") }
    var isPaired: Bool { familyID != nil && deviceToken != nil }

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
        do {
            let data = try await request(path: "/v1/families", method: "POST",
                                         body: try jsonData(["deviceName": deviceName]))
            let response = try JSONDecoder().decode(CreateFamilyResponse.self, from: data)
            try saveToken(response.deviceToken)
            familyID = response.familyId
            self.deviceName = deviceName
            pairingCode = response.pairingCode
            pairingCodeExpiry = Date(timeIntervalSince1970: TimeInterval(response.pairingCodeExpiresAt))
            UserDefaults.standard.set(response.familyId, forKey: "nelly.sync.familyID")
            UserDefaults.standard.set(deviceName, forKey: "nelly.sync.deviceName")
            statusMessage = "Family created. Enter this code on the second iPhone."
        } catch { statusMessage = error.localizedDescription }
    }

    func joinFamily(pairingCode: String, deviceName: String) async {
        guard isConfigured else {
            statusMessage = "The free sync server must be deployed before pairing."
            return
        }
        do {
            let data = try await request(path: "/v1/pair", method: "POST",
                                         body: try jsonData(["pairingCode": pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                                                             "deviceName": deviceName]))
            let response = try JSONDecoder().decode(PairFamilyResponse.self, from: data)
            try saveToken(response.deviceToken)
            familyID = response.familyId
            self.deviceName = deviceName
            self.pairingCode = nil
            pairingCodeExpiry = nil
            UserDefaults.standard.set(response.familyId, forKey: "nelly.sync.familyID")
            UserDefaults.standard.set(deviceName, forKey: "nelly.sync.deviceName")
            statusMessage = "This iPhone is paired successfully."
        } catch { statusMessage = error.localizedDescription }
    }

    func syncNow(library: LibraryStore, screenTime: ScreenTimeStore? = nil, pushLibraryMetadata: Bool = false) async {
        guard isConfigured, isPaired, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        statusMessage = "Checking the shared library…"
        do {
            if !UserDefaults.standard.bool(forKey: "nelly.sync.baselineCaptured") {
                let existingIDs = library.videos.filter { $0.kind == .file }.map { $0.id.uuidString }
                UserDefaults.standard.set(existingIDs, forKey: "nelly.sync.ignoredExistingIDs")
                UserDefaults.standard.set(true, forKey: "nelly.sync.baselineCaptured")
            }
            let ignoredIDs = Set(UserDefaults.standard.stringArray(forKey: "nelly.sync.ignoredExistingIDs") ?? [])
            var remote = try await fetchRemoteLibrary()
            for item in library.videos where item.kind == .file {
                guard !ignoredIDs.contains(item.id.uuidString) else { continue }
                guard !remote.videos.contains(where: { $0.id == item.id.uuidString }) else { continue }
                guard let fileURL = library.localURL(for: item) else { continue }
                try await uploadVideo(item, from: fileURL, position: library.videos.firstIndex(where: { $0.id == item.id }) ?? 0)
            }
            remote = try await fetchRemoteLibrary()
            if pushLibraryMetadata {
                for video in remote.videos where !video.isDeleted {
                    guard let id = UUID(uuidString: video.id),
                          let local = library.videos.first(where: { $0.id == id }) else {
                        // A peer's video that this phone has not downloaded yet is pending, not deleted.
                        if video.receivedByMe {
                            _ = try await request(path: "/v1/videos/\(video.id)/delete", method: "POST", body: Data("{}".utf8))
                        }
                        continue
                    }
                    let position = library.videos.firstIndex(where: { $0.id == id }) ?? video.position
                    let metadata: [String: Any] = [
                        "title": local.title ?? "", "enabled": local.enabled, "position": position
                    ]
                    _ = try await request(path: "/v1/videos/\(video.id)/meta", method: "PUT",
                                          body: try jsonData(metadata))
                }
            } else {
                for video in remote.videos {
                    guard let id = UUID(uuidString: video.id) else { continue }
                    if video.isDeleted {
                        if let local = library.videos.first(where: { $0.id == id }) { library.delete(local) }
                    } else {
                        library.applySyncedMetadata(id: id, title: video.title, enabled: video.enabled)
                    }
                }
                library.applySyncedOrder(remote.videos.filter { !$0.isDeleted }.sorted { $0.position < $1.position }
                    .compactMap { UUID(uuidString: $0.id) })
            }
            for video in remote.videos where !video.isDeleted && !video.receivedByMe && !video.relayDeleted {
                if let id = UUID(uuidString: video.id),
                   let existing = library.videos.first(where: { $0.id == id }),
                   library.localURL(for: existing) != nil {
                    try await acknowledge(video.id)
                    continue
                }
                try await downloadVideo(video, into: library)
            }
            if !pushLibraryMetadata {
                library.applySyncedOrder(remote.videos.filter { !$0.isDeleted }.sorted { $0.position < $1.position }
                    .compactMap { UUID(uuidString: $0.id) })
            }
            if let screenTime { try await syncScreenTime(screenTime) }
            lastSyncDate = Date()
            statusMessage = "Synced successfully."
        } catch {
            statusMessage = "Sync paused: \(error.localizedDescription). Your local videos are safe."
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
        UserDefaults.standard.removeObject(forKey: "nelly.sync.baselineCaptured")
        UserDefaults.standard.removeObject(forKey: "nelly.sync.ignoredExistingIDs")
        statusMessage = "Disconnected on this iPhone. Local videos are unchanged."
    }

    private func uploadVideo(_ item: VideoItem, from url: URL, position: Int) async throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size > 0, size <= maxVideoBytes else {
            throw SyncError.videoTooLarge
        }
        let count = Int(ceil(Double(size) / Double(chunkBytes)))
        let manifest: [String: Any] = [
            "byteCount": size, "chunkCount": count,
            "fileName": url.lastPathComponent, "title": item.title ?? "",
            "enabled": item.enabled, "position": position
        ]
        _ = try await request(path: "/v1/videos/\(item.id.uuidString)/manifest", method: "POST",
                              body: try jsonData(manifest))
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        for index in 0..<count {
            try Task.checkCancellation()
            let data = try handle.read(upToCount: chunkBytes) ?? Data()
            guard !data.isEmpty else { throw SyncError.fileReadFailed }
            _ = try await request(path: "/v1/videos/\(item.id.uuidString)/chunks/\(index)",
                                  method: "PUT", body: data, contentType: "application/octet-stream")
        }
        _ = try await request(path: "/v1/videos/\(item.id.uuidString)/complete", method: "POST",
                              body: Data("{}".utf8))
    }

    private func downloadVideo(_ video: RemoteVideo, into library: LibraryStore) async throws {
        guard video.byteCount > 0, video.byteCount <= maxVideoBytes,
              video.chunkCount > 0, video.chunkCount <= 25 else { throw SyncError.invalidManifest }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("Nelly-sync-\(UUID().uuidString).mp4")
        guard FileManager.default.createFile(atPath: temp.path, contents: nil) else {
            throw SyncError.fileWriteFailed
        }
        let handle = try FileHandle(forWritingTo: temp)
        defer { try? handle.close() }
        var received = 0
        do {
            for index in 0..<video.chunkCount {
                try Task.checkCancellation()
                let data = try await request(path: "/v1/videos/\(video.id)?chunk=\(index)", method: "GET")
                try handle.write(contentsOf: data)
                received += data.count
            }
            try handle.synchronize()
            guard received == video.byteCount else { throw SyncError.incompleteDownload }
            guard let id = UUID(uuidString: video.id) else { throw SyncError.invalidManifest }
            try library.importSyncedVideo(from: temp, fileName: video.fileName,
                                          id: id, title: video.title, enabled: video.enabled)
            try await acknowledge(video.id)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
        try? FileManager.default.removeItem(at: temp)
    }

    private func syncScreenTime(_ screenTime: ScreenTimeStore) async throws {
        let remoteData = try await request(path: "/v1/settings", method: "GET")
        let remote = try JSONDecoder().decode(RemoteSettings.self, from: remoteData)
        screenTime.applySharedState(dailyLimit: remote.dailyLimit, usedSeconds: remote.usedSeconds,
                                    usageDay: remote.usageDay, settingsUpdatedAt: remote.settingsUpdatedAt,
                                    resetAt: remote.resetAt)
        let payload: [String: Any] = [
            "dailyLimit": screenTime.dailyLimit,
            "usedSeconds": screenTime.usedSeconds,
            "usageDay": screenTime.sharedUsageDay,
            "settingsUpdatedAt": screenTime.sharedSettingsUpdatedAt,
            "resetAt": screenTime.sharedResetAt
        ]
        _ = try await request(path: "/v1/settings", method: "PUT", body: try jsonData(payload))
    }

    private func acknowledge(_ videoID: String) async throws {
        _ = try await request(path: "/v1/videos/\(videoID)/ack", method: "POST", body: Data("{}".utf8))
    }

    private func fetchRemoteLibrary() async throws -> RemoteLibrary {
        let data = try await request(path: "/v1/library", method: "GET")
        return try JSONDecoder().decode(RemoteLibrary.self, from: data)
    }

    private func request(path: String, method: String, body: Data? = nil,
                         contentType: String = "application/json") async throws -> Data {
        guard let base = URL(string: serviceURL),
              let url = URL(string: path, relativeTo: base) else { throw SyncError.notConfigured }
        guard let token = deviceToken, path != "/v1/families", path != "/v1/pair" else {
            return try await unauthenticatedRequest(url: url, method: method, body: body, contentType: contentType)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 120
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SyncError.serverRejected((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }

    private func unauthenticatedRequest(url: URL, method: String, body: Data?,
                                        contentType: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SyncError.serverRejected((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }

    private func jsonData(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
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
        guard status == errSecSuccess else { throw SyncError.keychainSaveFailed }
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
    private struct RemoteSettings: Decodable {
        let dailyLimit: Int
        let usedSeconds: Int
        let usageDay: String
        let settingsUpdatedAt: Double
        let resetAt: Double
    }
    private struct RemoteLibrary: Decodable {
        let videos: [RemoteVideo]
    }
    private struct RemoteVideo: Decodable {
        let id: String
        let fileName: String
        let title: String
        let enabled: Bool
        let position: Int
        let byteCount: Int
        let chunkCount: Int
        let relayDeleted: Bool
        let isDeleted: Bool
        let receivedByMe: Bool
    }
    private enum SyncError: LocalizedError {
        case notConfigured, videoTooLarge, fileReadFailed, fileWriteFailed
        case invalidManifest, incompleteDownload, keychainSaveFailed
        case serverRejected(Int)
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "The sync server address is not configured"
            case .videoTooLarge: return "This video is larger than the 100 MB test limit"
            case .fileReadFailed: return "Could not read the local video"
            case .fileWriteFailed: return "Could not create a temporary video file"
            case .invalidManifest: return "The server returned invalid video details"
            case .incompleteDownload: return "The downloaded video was incomplete"
            case .keychainSaveFailed: return "Could not securely save the pairing key"
            case .serverRejected(let code): return "The sync server returned HTTP \(code)"
            }
        }
    }
}
