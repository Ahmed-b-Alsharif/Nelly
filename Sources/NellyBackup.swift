import Foundation
import SwiftUI
import UIKit

private struct NellyBackupFile: Codable {
    let videoID: UUID
    let relativePath: String
    let byteCount: Int64
}

private struct NellyBackupManifest: Codable {
    let formatVersion: Int
    let createdAt: Date
    let videos: [VideoItem]
    let files: [NellyBackupFile]
}

enum NellyBackupBuilder {
    @MainActor
    static func createBackup(
        videos: [VideoItem],
        resolveLocalURL: (VideoItem) -> URL?
    ) throws -> URL {
        let fileManager = FileManager.default
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupFolder = fileManager.temporaryDirectory
            .appendingPathComponent("Nelly-Backup-\(timestamp)", isDirectory: true)
        let videosFolder = backupFolder.appendingPathComponent("Videos", isDirectory: true)

        try fileManager.createDirectory(at: videosFolder, withIntermediateDirectories: true)
        do {
            var backupFiles: [NellyBackupFile] = []
            var copiedNames = Set<String>()

            for item in videos where item.kind == .file {
                guard let sourceURL = resolveLocalURL(item),
                      fileManager.fileExists(atPath: sourceURL.path) else {
                    throw NellyBackupError.missingVideo(item.title ?? item.value)
                }

                let fileName = sourceURL.lastPathComponent
                guard !fileName.isEmpty,
                      fileName == item.value,
                      copiedNames.insert(fileName).inserted else {
                    throw NellyBackupError.invalidFileName
                }

                let sourceAttributes = try fileManager.attributesOfItem(atPath: sourceURL.path)
                let expectedSize = (sourceAttributes[.size] as? NSNumber)?.int64Value ?? 0
                guard expectedSize > 0 else {
                    throw NellyBackupError.emptyVideo(item.title ?? fileName)
                }

                let destinationURL = videosFolder.appendingPathComponent(fileName, isDirectory: false)
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                let copiedAttributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
                let copiedSize = (copiedAttributes[.size] as? NSNumber)?.int64Value ?? 0
                guard copiedSize == expectedSize else {
                    throw NellyBackupError.copyVerificationFailed(fileName)
                }

                backupFiles.append(NellyBackupFile(
                    videoID: item.id,
                    relativePath: "Videos/\(fileName)",
                    byteCount: copiedSize
                ))
            }

            let manifest = NellyBackupManifest(
                formatVersion: 1,
                createdAt: Date(),
                videos: videos,
                files: backupFiles
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let manifestData = try encoder.encode(manifest)
            let manifestURL = backupFolder.appendingPathComponent("NellyBackup.json")
            try manifestData.write(to: manifestURL, options: .atomic)

            // Verify the manifest and every copied file before presenting the export picker.
            let verifiedData = try Data(contentsOf: manifestURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            _ = try decoder.decode(NellyBackupManifest.self, from: verifiedData)
            guard backupFiles.count == videos.filter({ $0.kind == .file }).count else {
                throw NellyBackupError.copyVerificationFailed("Video count")
            }
            return backupFolder
        } catch {
            try? fileManager.removeItem(at: backupFolder)
            throw error
        }
    }
}


@MainActor
enum NellyBackupRestorer {
    static func restore(from folderURL: URL, into library: LibraryStore) throws -> Int {
        let manifestURL = folderURL.appendingPathComponent("NellyBackup.json")
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(NellyBackupManifest.self, from: data)
        guard manifest.formatVersion == 1 else { throw NellyBackupRestoreError.unsupportedVersion }

        let existingIDs = Set(library.videos.map(\.id))
        let pending = manifest.videos.filter { !existingIDs.contains($0.id) }
        if pending.isEmpty { return 0 }

        let filesByID = Dictionary(uniqueKeysWithValues: manifest.files.map { ($0.videoID, $0) })
        var fileSources: [UUID: URL] = [:]
        for item in pending where item.kind == .file {
            guard let entry = filesByID[item.id],
                  entry.relativePath.hasPrefix("Videos/"),
                  !entry.relativePath.contains("..") else {
                throw NellyBackupRestoreError.missingVideo(item.title ?? item.value)
            }
            let source = folderURL.appendingPathComponent(entry.relativePath)
            let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, Int64(values.fileSize ?? 0) == entry.byteCount else {
                throw NellyBackupRestoreError.invalidVideo(item.title ?? item.value)
            }
            fileSources[item.id] = source
        }

        var restored = 0
        for item in pending {
            if item.kind == .file {
                guard let source = fileSources[item.id] else { continue }
                try library.importRestoredVideo(from: source, item: item)
            } else {
                library.videos.append(item)
            }
            restored += 1
        }
        return restored
    }
}

private enum NellyBackupRestoreError: LocalizedError {
    case unsupportedVersion
    case missingVideo(String)
    case invalidVideo(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "This backup version is not supported."
        case .missingVideo(let name): return "The backup is missing the video: \(name). No existing videos were changed."
        case .invalidVideo(let name): return "The backup video could not be verified: \(name). No existing videos were changed."
        }
    }
}

struct NellyBackupDocumentPicker: UIViewControllerRepresentable {
    let folderURL: URL
    let onComplete: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [folderURL], asCopy: true)
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onComplete: (Bool) -> Void

        init(onComplete: @escaping (Bool) -> Void) {
            self.onComplete = onComplete
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onComplete(!urls.isEmpty)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onComplete(false)
        }
    }
}

private enum NellyBackupError: LocalizedError {
    case missingVideo(String)
    case emptyVideo(String)
    case invalidFileName
    case copyVerificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingVideo(let name):
            return "The video '\(name)' is missing from this iPhone. No backup was exported."
        case .emptyVideo(let name):
            return "The video '\(name)' is empty. No backup was exported."
        case .invalidFileName:
            return "A video has an invalid or duplicate file name. No backup was exported."
        case .copyVerificationFailed(let name):
            return "The copied file '\(name)' did not pass verification. No backup was exported."
        }
    }
}
