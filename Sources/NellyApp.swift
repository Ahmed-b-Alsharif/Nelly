import SwiftUI

@main
struct NellyApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var screenTime = ScreenTimeStore()
    @AppStorage("nelly.theme.dark") private var darkMode = false

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(library)
                .environmentObject(screenTime)
                .preferredColorScheme(darkMode ? .dark : .light)
        }
    }
}
