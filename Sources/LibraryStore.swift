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
    }

    var activeVideos: [VideoItem] { videos.filter(\.enabled) }

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

    func importVideo(data: Data, fileName: String) throws {
        let folder = try documentsFolder()
        let safeName = UUID().uuidString + "-" + (fileName as NSString).lastPathComponent
        try data.write(to: folder.appendingPathComponent(safeName), options: .atomic)
        videos.append(VideoItem(kind: .file, value: safeName))
    }

    func localURL(for item: VideoItem) -> URL? {
        guard item.kind == .file else { return nil }
        return try? documentsFolder().appendingPathComponent(item.value)
    }

    func update(_ item: VideoItem, value: String, title: String) throws {
        var updated = item
        if item.kind != .file {
            guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let host = url.host, host.contains("."),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                throw LibraryError.invalidLink
            }
            updated.value = url.absoluteString
        }
        updated.title = title.isEmpty ? nil : title
        if let index = videos.firstIndex(where: { $0.id == item.id }) {
            videos[index] = updated
        }
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

    private func documentsFolder() throws -> URL {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(videos) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum LibraryError: LocalizedError {
    case invalidLink
    var errorDescription: String? { "Please enter a valid video link." }
}
