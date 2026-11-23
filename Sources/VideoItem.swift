import Foundation

enum VideoKind: String, Codable {
    case file, tiktok, youtube, website
}

struct VideoItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: VideoKind
    var value: String
    var enabled: Bool = true
    var addedAt: Date = Date()
    var title: String? = nil
    var description: String? = nil
}
