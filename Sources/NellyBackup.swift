import Foundation
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
            .appendingPathComponent("Nelly-Backup-\\(timestamp)", isDirectory: true)
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
                    relativePath: "Videos/\\(fileName)",
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
            _ = try JSONDecoder().decode(NellyBackupManifest.self, from: verifiedData)
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
            return "The video '\\(name)' is missing from this iPhone. No backup was exported."
        case .emptyVideo(let name):
            return "The video '\\(name)' is empty. No backup was exported."
        case .invalidFileName:
            return "A video has an invalid or duplicate file name. No backup was exported."
        case .copyVerificationFailed(let name):
            return "The copied file '\\(name)' did not pass verification. No backup was exported."
        }
    }
}
