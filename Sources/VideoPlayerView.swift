import SwiftUI
import AVKit
import WebKit
import AVFoundation

struct VideoPlayerView: View {
    let item: VideoItem
    let isPlaying: Bool

    var body: some View {
        Group {
            switch item.kind {
            case .file:
                if let url = localURL {
                    LoopingPlayer(url: url, isPlaying: isPlaying)
                } else {
                    unavailable
                }
            case .tiktok:
                if let url = tiktokPlayerURL {
                    EmbeddedWebVideo(url: url, isPlaying: isPlaying)
                } else {
                    unavailable
                }
            case .youtube:
                if let url = youtubeEmbedURL {
                    EmbeddedWebVideo(url: url, isPlaying: isPlaying)
                } else {
                    unavailable
                }
            case .website:
                if let url = directVideoURL {
                    LoopingPlayer(url: url, isPlaying: isPlaying)
                } else {
                    unavailable
                }
            }
        }
        .background(Color.black)
        .onAppear { configureAudio() }
    }

    private var localURL: URL? {
        guard item.kind == .file else { return nil }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(item.value)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // Only direct video files are played from generic website links. Ordinary web pages
    // are never opened as a browser inside the child feed.
    private var directVideoURL: URL? {
        guard let url = URL(string: item.value),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              ["mp4", "m4v", "mov", "m3u8"].contains(url.pathExtension.lowercased()) else {
            return nil
        }
        return url
    }

    private var tiktokPlayerURL: URL? {
        guard let url = URL(string: item.value),
              url.host?.lowercased().contains("tiktok.com") == true else { return nil }
        let parts = url.pathComponents
        guard let index = parts.firstIndex(of: "video"),
              parts.indices.contains(index + 1),
              !parts[index + 1].isEmpty else { return nil }
        return URL(string: "https://www.tiktok.com/player/v1/\(parts[index + 1])?autoplay=1&loop=1&controls=0&music_info=0&description=0")
    }

    private var youtubeEmbedURL: URL? {
        guard let url = URL(string: item.value) else { return nil }
        let host = url.host?.lowercased() ?? ""
        let id: String?
        if host == "youtu.be" {
            id = url.pathComponents.last
        } else if host.contains("youtube.com") {
            id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "v" })?.value
                ?? url.pathComponents.drop(while: { $0 != "embed" }).dropFirst().first
        } else {
            id = nil
        }
        guard let id, !id.isEmpty else { return nil }
        return URL(string: "https://www.youtube-nocookie.com/embed/\(id)?autoplay=1&mute=0&loop=1&playlist=\(id)&controls=0&rel=0&playsinline=1&enablejsapi=1")
    }

    private var unavailable: some View {
        VStack(spacing: 14) {
            Image(systemName: "video.slash")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            Text("This video can't be played inside Nelly")
                .font(.system(size: 19, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Text("Please ask a parent to add the video from Photos or Files.")
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(28)
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

private func configureAudio() {
    do {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .moviePlayback, options: [])
        try session.setActive(true)
    } catch {
        // Keep playback available even if the audio session cannot be changed.
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
                configureAudio()
                let queue = AVQueuePlayer()
                queue.isMuted = false
                queue.volume = 1
                queue.automaticallyWaitsToMinimizeStalling = true
                looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
                player = queue
                if isPlaying { queue.play() }
            }
            .onChange(of: isPlaying) { _, value in
                if value {
                    player?.isMuted = false
                    player?.volume = 1
                    player?.play()
                } else {
                    player?.pause()
                }
            }
            .onDisappear {
                player?.pause()
                player = nil
                looper = nil
            }
    }
}

private struct VideoLayer: UIViewControllerRepresentable {
    let player: AVPlayer?

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        // Fit the entire video in the screen without cropping faces or important content.
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

private struct EmbeddedWebVideo: View {
    let url: URL
    let isPlaying: Bool
    @State private var hasFailed = false

    var body: some View {
        Group {
            if hasFailed {
                VStack(spacing: 14) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 42, weight: .medium))
                    Text("This video can't be played inside Nelly")
                        .font(.system(size: 19, weight: .semibold))
                        .multilineTextAlignment(.center)
                    Text("Please ask a parent to add the video from Photos or Files.")
                        .font(.system(size: 15))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.72))
                }
                .foregroundStyle(.white)
                .padding(28)
                .frame(maxWidth: 320)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else {
                EmbeddedWebView(url: url, isPlaying: isPlaying) {
                    hasFailed = true
                }
            }
        }
        .background(Color.black)
        .onAppear { configureAudio() }
    }
}

private struct EmbeddedWebView: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool
    let onUnavailable: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(embedURL: url, onUnavailable: onUnavailable)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        // The child feed is not a browser: taps cannot activate links or leave Nelly.
        web.isUserInteractionEnabled = false
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.onUnavailable = onUnavailable
        let command = isPlaying ? "playVideo" : "pauseVideo"
        let shouldPlay = isPlaying ? "true" : "false"
        let js = """
        document.querySelectorAll('video').forEach(v => {
            v.muted = false;
            v.volume = 1;
            if ("\(shouldPlay)" === "true") {
                const result = v.play();
                if (result) result.catch(() => {});
            } else {
                v.pause();
            }
        });
        document.querySelectorAll('iframe').forEach(f => {
            f.contentWindow?.postMessage(
                JSON.stringify({event:'command', func:'\(command)', args:''}), '*'
            );
        });
        """
        web.evaluateJavaScript(js, completionHandler: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let embedURL: URL
        var onUnavailable: () -> Void

        init(embedURL: URL, onUnavailable: @escaping () -> Void) {
            self.embedURL = embedURL
            self.onUnavailable = onUnavailable
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            reportFailureUnlessCancelled(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            reportFailureUnlessCancelled(error)
        }

        private func reportFailureUnlessCancelled(_ error: Error) {
            let nsError = error as NSError
            if nsError.code != NSURLErrorCancelled {
                onUnavailable()
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            onUnavailable()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Some providers return an error page with a successful HTTP navigation.
            let script = """
            (() => {
                const text = (document.body?.innerText || '').toLowerCase();
                return [
                    'video unavailable',
                    'video is unavailable',
                    'embedding disabled',
                    'playback is restricted',
                    'this video cannot be played',
                    'this video is not available'
                ].some(message => text.includes(message));
            })();
            """
            webView.evaluateJavaScript(script) { result, _ in
                if (result as? Bool == true) {
                    self.onUnavailable()
                }
            }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Only allow the embed's own HTTP(S) loading. Never follow user-activated links,
            // open new windows, or hand a URL to another app.
            guard let destination = navigationAction.request.url,
                  ["http", "https"].contains(destination.scheme?.lowercased() ?? ""),
                  navigationAction.navigationType != .linkActivated,
                  let targetFrame = navigationAction.targetFrame else {
                decisionHandler(.cancel)
                return
            }

            // The main frame must remain on the original provider embed URL. This prevents
            // redirects to a full TikTok/YouTube page, while allowing provider subframes.
            if targetFrame.isMainFrame {
                let sameEmbed = destination.host == embedURL.host
                    && destination.path.hasPrefix(embedURL.path)
                decisionHandler(sameEmbed ? .allow : .cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
