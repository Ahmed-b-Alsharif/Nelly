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
                if let url = tiktokPlayerURL { EmbeddedWebVideo(url: url, isPlaying: isPlaying) }
                else { unavailable }
            case .youtube:
                if let url = youtubeEmbedURL { EmbeddedWebVideo(url: url, isPlaying: isPlaying) }
                else { unavailable }
            case .website:
                if let url = URL(string: item.value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                    EmbeddedWebVideo(url: url, isPlaying: isPlaying)
                } else { unavailable }
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
        return URL(string: "https://www.tiktok.com/player/v1/\(parts[index + 1])?autoplay=1&loop=1&controls=0&music_info=0&description=0")
    }

    private var youtubeEmbedURL: URL? {
        guard let url = URL(string: item.value) else { return nil }
        let id: String?
        if url.host == "youtu.be" { id = url.pathComponents.last }
        else { id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value }
        guard let id else { return nil }
        return URL(string: "https://www.youtube-nocookie.com/embed/\(id)?autoplay=1&mute=0&loop=1&playlist=\(id)&controls=0&rel=0&playsinline=1&enablejsapi=1")
    }

    private var unavailable: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash").font(.largeTitle)
            Text("This video can't play inside Nelly")
            Text("Try importing the video from Photos or Files.")
                .font(.caption).foregroundStyle(.white.opacity(0.7))
        }.multilineTextAlignment(.center).foregroundStyle(.white).padding()
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
                queue.isMuted = false
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
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .black
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
    }
}

private struct EmbeddedWebVideo: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.scrollView.isScrollEnabled = false
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.isUserInteractionEnabled = false
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        let command = isPlaying ? "playVideo" : "pauseVideo"
        let js = """
        document.querySelectorAll('video').forEach(v => {
            v.muted = false;
            v.volume = 1;
            if ("\(isPlaying)" === "true") { const p = v.play(); if (p) p.catch(() => {}); }
            else { v.pause(); }
        });
        document.querySelectorAll('iframe').forEach(f => {
            f.contentWindow?.postMessage(JSON.stringify({event:'command', func:'\(command)', args:''}), '*');
        });
        """
        web.evaluateJavaScript(js, completionHandler: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Keep every tap inside Nelly. Only allow page loads and redirects initiated by the embed itself.
            if navigationAction.navigationType == .linkActivated || navigationAction.targetFrame == nil {
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
