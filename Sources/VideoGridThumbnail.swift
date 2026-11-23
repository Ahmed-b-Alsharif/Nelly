import SwiftUI
import AVFoundation

struct VideoGridThumbnail: View {
    let item: VideoItem
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            Color.black
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 34))
                    Text("Nelly video")
                        .font(.caption)
                }
                .foregroundStyle(.white.opacity(0.8))
            }
            VStack {
                Spacer()
                HStack {
                    Image(systemName: "play.fill")
                    Spacer()
                    Text(" ")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(7)
                .background(.black.opacity(0.35))
            }
        }
        .task(id: item.value) {
            guard item.kind == .file else { return }
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let url = support.appendingPathComponent("NellyVideos", isDirectory: true)
                .appendingPathComponent(item.value, isDirectory: false)
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            do {
                let asset = AVURLAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 500, height: 700)
                let frame = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600))
                thumbnail = UIImage(cgImage: frame.image)
            } catch {
                thumbnail = nil
            }
        }
    }
}
