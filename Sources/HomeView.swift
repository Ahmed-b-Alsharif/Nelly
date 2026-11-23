import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var screenTime: ScreenTimeStore
    @AppStorage("nelly.adminPIN") private var adminPIN = "2468"
    @State private var showPIN = false
    @State private var showAdmin = false
    @State private var pin = ""
    @State private var pinError = false
    @State private var currentVideoID: UUID?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if library.activeVideos.isEmpty { emptyState }
            else if screenTime.isLimitReached { limitScreen }
            else { feed }

            Button { showPIN = true } label: {
                Image(systemName: "lock.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(13)
                    .background(.black.opacity(0.38), in: Circle())
            }
            .padding(.top, 12).padding(.trailing, 16)
            .accessibilityLabel("Parent admin")
        }
        .statusBarHidden()
        .sheet(isPresented: $showPIN) { pinSheet }
        .sheet(isPresented: $showAdmin) { AdminView() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if !showAdmin && !showPIN && !library.activeVideos.isEmpty { screenTime.tick() }
            }
        }
        .onChange(of: currentVideoID) { _, newID in
            if let item = library.activeVideos.first(where: { $0.id == newID }) {
                library.recordWatch(item)
            }
        }
        .onChange(of: library.activeVideos) { _, active in
            if !active.contains(where: { $0.id == currentVideoID }) {
                currentVideoID = active.first?.id
            }
        }
    }

    private var feed: some View {
        GeometryReader { geo in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(library.activeVideos) { item in
                        ZStack {
                            VideoPlayerView(item: item, isPlaying: screenTime.isPlaying && currentVideoID == item.id)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Button { screenTime.setPlaying(!screenTime.isPlaying) } label: {
                                        Image(systemName: screenTime.isPlaying ? "pause.fill" : "play.fill")
                                            .font(.system(size: 23, weight: .bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 58, height: 58)
                                            .background(.black.opacity(0.48), in: Circle())
                                            .overlay(Circle().stroke(.white.opacity(0.75), lineWidth: 1))
                                    }
                                    .accessibilityLabel(screenTime.isPlaying ? "Pause video" : "Play video")
                                }.padding(.trailing, 22).padding(.bottom, 34)
                            }
                        }
                        .containerRelativeFrame(.vertical)
                        .id(item.id)
                    }
                }.scrollTargetLayout()
            }
            .scrollPosition(id: $currentVideoID)
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .onAppear { if currentVideoID == nil { currentVideoID = library.activeVideos.first?.id } }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "butterfly.fill").font(.system(size: 70)).foregroundStyle(.pink)
            Text("Nelly").font(.largeTitle.bold()).foregroundStyle(.white)
            Text("Your videos will be here").foregroundStyle(.white.opacity(0.7))
        }
    }

    private var limitScreen: some View {
        VStack(spacing: 18) {
            Image(systemName: "heart.fill").font(.system(size: 54)).foregroundStyle(.pink)
            Text("That's enough for today").font(.title2.bold())
            Text("Come back tomorrow for more videos.")
        }.foregroundStyle(.white)
    }

    private var pinSheet: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(.pink)
                Text("Parent access").font(.title2.bold())
                SecureField("Enter PIN", text: $pin).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                if pinError { Text("Incorrect PIN").foregroundStyle(.red) }
                Button("Unlock admin") {
                    if pin == adminPIN {
                        pin = ""; pinError = false; showPIN = false; showAdmin = true
                    } else { pinError = true; pin = "" }
                }.buttonStyle(.borderedProminent).tint(.pink)
                Text("Default PIN: 2468 — change it in Admin.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding()
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { showPIN = false } } }
        }.presentationDetents([.medium])
    }
}
