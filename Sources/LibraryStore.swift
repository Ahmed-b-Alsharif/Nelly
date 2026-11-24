import Foundation
import SwiftUI

@MainActor
final class LibraryStore: ObservableObject {
    @Published var videos: [VideoItem] = [] { didSet { persist() } }
    @Published var watchHistory: [String] = [] {
        didSet { UserDefaults.standard.set(watchHistory, forKey: "nelly.history") }
    }
    private let key = "nelly.library.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([VideoItem].self, from: data) {
            videos = saved
        }
        watchHistory = UserDefaults.standard.stringArray(forKey: "nelly.history") ?? []
        migrateLegacyDocumentsIfNeeded()
    }

    var activeVideos: [VideoItem] { videos.filter { $0.enabled && $0.kind == .file } }

    func addLink(_ raw: String) throws {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased(), host.contains("."),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw LibraryError.invalidLink
        }
        let kind: VideoKind
        if host.contains("tiktok.com") { kind = .tiktok }
        else if host.contains("youtube.com") || host == "youtu.be" { kind = .youtube }
        else { kind = .website }
        videos.append(VideoItem(kind: kind, value: url.absoluteString))
    }

    func importVideo(from sourceURL: URL, fileName: String) throws {
        let folder = try privateVideoFolder()
        let sourceName = (fileName as NSString).lastPathComponent
        let ext = (sourceName as NSString).pathExtension
        let base = (sourceName as NSString).deletingPathExtension
        let safeBase = base.isEmpty ? "Video" : base
        let safeName = UUID().uuidString + "-" + safeBase + (ext.isEmpty ? "" : ".\(ext)")
        let destination = folder.appendingPathComponent(safeName, isDirectory: false)
        let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) > 0 else {
            throw LibraryError.invalidVideo
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        videos.append(VideoItem(kind: .file, value: safeName))
    }

    func importSyncedVideo(from sourceURL: URL, fileName: String, id: UUID, title: String) throws {
        guard !videos.contains(where: { $0.id == id }) else { return }
        let folder = try privateVideoFolder()
        let sourceName = (fileName as NSString).lastPathComponent
        let ext = (sourceName as NSString).pathExtension
        let base = (sourceName as NSString).deletingPathExtension
        let safeBase = base.isEmpty ? "Video" : base
        let safeName = UUID().uuidString + "-" + safeBase + (ext.isEmpty ? "" : ".\(ext)")
        let destination = folder.appendingPathComponent(safeName, isDirectory: false)
        let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) > 0 else {
            throw LibraryError.invalidVideo
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        videos.append(VideoItem(id: id, kind: .file, value: safeName, enabled: true,
                                addedAt: Date(), title: title.isEmpty ? nil : title))
    }

    func localURL(for item: VideoItem) -> URL? {
        guard item.kind == .file else { return nil }
        guard let folder = try? privateVideoFolder() else { return nil }
        let url = folder.appendingPathComponent(item.value, isDirectory: false)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func update(_ item: VideoItem, value: String, title: String) throws {
        // Update the current stored record by stable ID. Do not replace the
        // file-backed item with the older snapshot passed to the editor sheet.
        guard let index = videos.firstIndex(where: { $0.id == item.id }) else {
            throw LibraryError.videoNotFound
        }

        if videos[index].kind != .file {
            guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let host = url.host, host.contains("."),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                throw LibraryError.invalidLink
            }
            videos[index].value = url.absoluteString
        }
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        videos[index].title = cleanedTitle.isEmpty ? nil : cleanedTitle
    }

    func delete(_ item: VideoItem) {
        if let url = localURL(for: item) { try? FileManager.default.removeItem(at: url) }
        videos.removeAll { $0.id == item.id }
    }

    func move(from source: IndexSet, to destination: Int) {
        videos.move(fromOffsets: source, toOffset: destination)
    }

    func recordWatch(_ item: VideoItem) {
        watchHistory.insert(item.value, at: 0)
        watchHistory = Array(watchHistory.prefix(100))
    }

    private func privateVideoFolder() throws -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appendingPathComponent("NellyVideos", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableFolder = folder
        try? mutableFolder.setResourceValues(values)
        return folder
    }

    private func migrateLegacyDocumentsIfNeeded() {
        guard let destination = try? privateVideoFolder() else { return }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for item in videos where item.kind == .file {
            let oldURL = documents.appendingPathComponent(item.value)
            let newURL = destination.appendingPathComponent(item.value)
            if FileManager.default.fileExists(atPath: oldURL.path),
               !FileManager.default.fileExists(atPath: newURL.path) {
                try? FileManager.default.moveItem(at: oldURL, to: newURL)
            }
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(videos) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum LibraryError: LocalizedError {
    case invalidLink
    case invalidVideo
    case videoNotFound
    var errorDescription: String? {
        switch self {
        case .invalidLink: return "Please enter a valid video link."
        case .invalidVideo: return "The selected file is not a readable video."
        case .videoNotFound: return "This video is no longer in the library. Close the editor and refresh the library."
        }
    }
}
