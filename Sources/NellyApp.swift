import SwiftUI
import AVFoundation

@main
struct NellyApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var screenTime = ScreenTimeStore()
    @AppStorage("nelly.theme.dark") private var darkMode = false

    init() {
        // Use the iPhone's hardware volume controls; Nelly has no in-app mute control.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(library)
                .environmentObject(screenTime)
                .preferredColorScheme(darkMode ? .dark : .light)
        }
    }
}
