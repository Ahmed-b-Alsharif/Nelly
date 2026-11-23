import SwiftUI
import AVKit
import AVFoundation

struct VideoPlayerView: View {
    let item: VideoItem
    let isPlaying: Bool

    var body: some View {
        Group {
            if let url = localURL {
                LoopingPlayer(url: url, isPlaying: isPlaying)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("This video is no longer available")
                        .font(.system(size: 19, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    Text("Please ask a parent to import it again from Photos or Files.")
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
        .background(Color.black)
        .onAppear { configureAudio() }
    }

    private var localURL: URL? {
        guard item.kind == .file else { return nil }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = support.appendingPathComponent("NellyVideos", isDirectory: true)
            .appendingPathComponent(item.value, isDirectory: false)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

private func configureAudio() {
    do {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .moviePlayback, options: [])
        try session.setActive(true)
    } catch { }
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
                } else { player?.pause() }
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
