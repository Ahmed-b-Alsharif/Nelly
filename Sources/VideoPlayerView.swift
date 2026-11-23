import SwiftUI
import AVKit
import WebKit

struct VideoPlayerView: View {
    let item: VideoItem
    let isPlaying: Bool

    var body: some View {
        Group {
            switch item.kind {
            case .file:
                if let url = localURL { LoopingPlayer(url: url, isPlaying: isPlaying) }
                else { unavailable }
            case .tiktok:
                EmbeddedWebVideo(url: tiktokPlayerURL ?? URL(string: item.value)!, isPlaying: isPlaying)
            case .youtube:
                EmbeddedWebVideo(url: youtubeEmbedURL ?? URL(string: item.value)!, isPlaying: isPlaying)
            case .website:
                EmbeddedWebVideo(url: URL(string: item.value)!, isPlaying: isPlaying)
            }
        }
        .background(.black)
    }

    private var localURL: URL? {
        guard item.kind == .file else { return nil }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(item.value)
    }

    private var tiktokPlayerURL: URL? {
        guard let url = URL(string: item.value) else { return nil }
        let parts = url.pathComponents
        guard let index = parts.firstIndex(of: "video"), parts.indices.contains(index + 1) else { return nil }
        return URL(string: "https://www.tiktok.com/player/v1/\(parts[index + 1])?autoplay=1&loop=1&controls=0")
    }

    private var youtubeEmbedURL: URL? {
        guard let url = URL(string: item.value) else { return nil }
        let id: String?
        if url.host == "youtu.be" { id = url.pathComponents.last }
        else { id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value }
        guard let id else { return nil }
        return URL(string: "https://www.youtube-nocookie.com/embed/\(id)?autoplay=1&loop=1&playlist=\(id)&controls=0&rel=0")
    }

    private var unavailable: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash").font(.largeTitle)
            Text("This video is unavailable")
        }.foregroundStyle(.white)
    }
}

private struct LoopingPlayer: View {
    let url: URL
    let isPlaying: Bool
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        VideoLayer(player: player)
            .onAppear {
                let queue = AVQueuePlayer()
                looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
                player = queue
                if isPlaying { queue.play() }
            }
            .onChange(of: isPlaying) { _, value in
                if value { player?.play() } else { player?.pause() }
            }
            .onDisappear { player?.pause(); player = nil; looper = nil }
    }
}

private struct VideoLayer: UIViewControllerRepresentable {
    let player: AVPlayer?
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
    }
}

private struct EmbeddedWebVideo: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.scrollView.isScrollEnabled = false
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        web.evaluateJavaScript(isPlaying
            ? "document.querySelectorAll('video').forEach(v => v.play())"
            : "document.querySelectorAll('video').forEach(v => v.pause())")
    }
}
