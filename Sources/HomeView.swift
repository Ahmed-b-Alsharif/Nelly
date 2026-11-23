import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var screenTime: ScreenTimeStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("nelly.adminPIN") private var adminPIN = "2468"
    @AppStorage("nelly.pinConfigured") private var pinConfigured = false
    @AppStorage("nelly.pinFailedAttempts") private var failedAttempts = 0
    @AppStorage("nelly.pinLockedUntil") private var lockedUntil = 0.0
    @State private var showPIN = false
    @State private var showAdmin = false
    @State private var pin = ""
    @State private var confirmPIN = ""
    @State private var pinError = ""
    @State private var currentVideoID: UUID?
    @State private var playbackVideos: [VideoItem] = []
    @State private var previousVideoID: UUID?
    @State private var showGrid = false
    @State private var limitPIN = ""
    @State private var limitPINError = ""

    private var isLockedOut: Bool { Date().timeIntervalSince1970 < lockedUntil }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if library.activeVideos.isEmpty {
                emptyState
            } else if screenTime.isLimitReached {
                limitScreen
            } else if showGrid {
                videoGrid
            } else {
                feed
            }
            Button { showPIN = true } label: {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.42), in: Circle())
            }
            .padding(.top, 12)
            .padding(.trailing, 16)
            .accessibilityLabel("Parent admin")
        }
        .statusBarHidden()
        .sheet(isPresented: $showPIN) { pinSheet }
        .sheet(isPresented: $showAdmin) { AdminView() }
        .onAppear {
            if !pinConfigured { showPIN = true }
            prepareRandomPlayback()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if scenePhase == .active && !showAdmin && !showPIN && !library.activeVideos.isEmpty {
                    screenTime.tick()
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                screenTime.setPlaying(false)
            } else {
                prepareRandomPlayback()
            }
        }
        .onChange(of: currentVideoID) { oldID, newID in
            if let item = playbackVideos.first(where: { $0.id == newID }) {
                library.recordWatch(item)
                if oldID != nil, let lastID = playbackVideos.last?.id, newID == lastID {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        if currentVideoID == lastID {
                            currentVideoID = playbackVideos.first?.id
                        }
                    }
                }
                previousVideoID = newID
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
                    ForEach(playbackVideos) { item in
                        ZStack {
                            VideoPlayerView(item: item, isPlaying: screenTime.isPlaying && currentVideoID == item.id && scenePhase == .active)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()

                            // TikTok-inspired visual chrome. These are presentation-only:
                            // Nelly remains a private, parent-curated offline video player.
                            feedChrome(for: item)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .allowsHitTesting(false)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            screenTime.setPlaying(!screenTime.isPlaying)
                        }
                        .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
                            let dx = value.translation.width
                            let dy = value.translation.height
                            if abs(dx) > abs(dy) && dx < -70 {
                                showGrid = true
                                screenTime.setPlaying(false)
                            }
                        })
                        .containerRelativeFrame(.vertical)
                        .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $currentVideoID)
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .onAppear {
                if currentVideoID == nil {
                    currentVideoID = library.activeVideos.first?.id
                }
            }
        }
        .ignoresSafeArea()
    }

    private var videoGrid: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    showGrid = false
                    resetFeedToBeginningIfNeeded()
                } label: { Image(systemName: "chevron.left").font(.title3.weight(.semibold)) }
                Text("Videos").font(.headline)
                Spacer()
                Text("\(library.activeVideos.count) videos").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)], spacing: 8) {
                    ForEach(library.activeVideos) { item in
                        Button {
                            currentVideoID = item.id
                            showGrid = false
                            screenTime.setPlaying(true)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                VideoGridThumbnail(item: item).frame(height: 220).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(item.title?.isEmpty == false ? item.title! : "Video")
                                    .font(.caption).lineLimit(2).foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 5).padding(.bottom, 20)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
            if value.translation.width > 70 && abs(value.translation.width) > abs(value.translation.height) {
                showGrid = false
                resetFeedToBeginningIfNeeded()
            }
        })
    }

    private func resetFeedToBeginningIfNeeded() {
        if playbackVideos.isEmpty { playbackVideos = library.activeVideos.shuffled() }
        if currentVideoID == nil { currentVideoID = playbackVideos.randomElement()?.id }
        screenTime.setPlaying(!screenTime.isLimitReached)
    }

    private func feedChrome(for item: VideoItem) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .semibold))
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text("Search videos")
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Rectangle()
                        .fill(.white.opacity(0.55))
                        .frame(width: 1, height: 22)
                    Text("Search")
                        .fontWeight(.semibold)
                }
                .font(.system(size: 16))
                .padding(.horizontal, 13)
                .frame(height: 48)
                .background(.ultraThinMaterial.opacity(0.78), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.8), lineWidth: 1))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.top, 54)

            Spacer()

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nelly • Parent's library")
                        .font(.system(size: 15, weight: .semibold))
                    Text(item.title?.isEmpty == false ? item.title! : "A video picked for you")
                        .font(.system(size: 15))
                        .lineLimit(2)
                    Text("Saved videos • Watch offline")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.88))
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass")
                        Text("More videos in your library")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 11)
                    .frame(height: 38)
                    .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 22) {
                    feedAction("person.crop.circle.fill", label: "Parent")
                    feedAction("heart.fill", label: "Like")
                    feedAction("bubble.right.fill", label: "Comment")
                    feedAction("bookmark.fill", label: "Save")
                    feedAction("arrowshape.turn.up.right.fill", label: "Share")
                }
                .padding(.bottom, 8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.bottom, 34)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.28), .black.opacity(0.48)],
                               startPoint: .top, endPoint: .bottom)
            )
        }
    }

    private func feedAction(_ symbol: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 29, weight: .semibold))
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
        }
    }

    private func prepareRandomPlayback() {
        playbackVideos = library.activeVideos.shuffled()
        currentVideoID = playbackVideos.randomElement()?.id
        screenTime.setPlaying(!screenTime.isLimitReached)
    }

    private func resetFeedToBeginning() {
        if playbackVideos.isEmpty { playbackVideos = library.activeVideos.shuffled() }
        currentVideoID = playbackVideos.randomElement()?.id
        screenTime.setPlaying(!screenTime.isLimitReached)
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
            Image(systemName: "lock.fill").font(.system(size: 54)).foregroundStyle(.pink)
            Text("Screen time is over").font(.title2.bold())
            Text("Ask a parent to enter their PIN to continue.").multilineTextAlignment(.center)
            SecureField("Parent PIN", text: $limitPIN)
                .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240).multilineTextAlignment(.center)
            if !limitPINError.isEmpty { Text(limitPINError).font(.caption).foregroundStyle(.red) }
            Button("Parent unlock") {
                guard pinConfigured, limitPIN == adminPIN else {
                    limitPIN = ""
                    limitPINError = "Incorrect PIN. Ask a parent for help."
                    return
                }
                limitPIN = ""
                limitPINError = ""
                screenTime.parentOverride()
                showGrid = false
                resetFeedToBeginning()
            }
            .buttonStyle(.borderedProminent).tint(.pink)
            .disabled(!pinConfigured || limitPIN.isEmpty)
            Text("Nelly stays locked until a parent approves more time.")
                .font(.footnote).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center)
        }
        .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black).foregroundStyle(.white)
    }

    private var pinSheet: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(.pink)
                Text(pinConfigured ? "Parent access" : "Create your parent PIN").font(.title2.bold())

                if pinConfigured {
                    SecureField("Enter PIN", text: $pin).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                    if !pinError.isEmpty { Text(pinError).foregroundStyle(.red) }
                    if isLockedOut {
                        Text("Too many attempts. Try again in \(max(1, Int(ceil(lockedUntil - Date().timeIntervalSince1970)) / 60)) minute(s).")
                            .font(.caption).foregroundStyle(.red)
                    }
                    Button("Unlock admin") {
                        guard !isLockedOut else { return }
                        if pin == adminPIN {
                            pin = ""
                            pinError = ""
                            failedAttempts = 0
                            showPIN = false
                            showAdmin = true
                        } else {
                            failedAttempts += 1
                            pinError = "Incorrect PIN."
                            pin = ""
                            if failedAttempts >= 5 {
                                lockedUntil = Date().timeIntervalSince1970 + 60
                                failedAttempts = 0
                            }
                        }
                    }
                    .disabled(isLockedOut)
                } else {
                    SecureField("New PIN (4–12 digits)", text: $pin).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                    SecureField("Confirm new PIN", text: $confirmPIN).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                    if !pinError.isEmpty { Text(pinError).foregroundStyle(.red) }
                    Button("Save parent PIN") {
                        guard pin.count >= 4, pin.count <= 12, pin.allSatisfy(\.isNumber) else {
                            pinError = "Choose a PIN with 4 to 12 digits."
                            return
                        }
                        guard pin == confirmPIN else {
                            pinError = "The PINs do not match."
                            return
                        }
                        adminPIN = pin
                        pinConfigured = true
                        pin = ""
                        confirmPIN = ""
                        pinError = ""
                        showPIN = false
                        showAdmin = true
                    }
                    .buttonStyle(.borderedProminent).tint(.pink)
                }
            }
            .padding()
            .toolbar {
                if pinConfigured {
                    ToolbarItem(placement: .topBarTrailing) { Button("Close") { showPIN = false } }
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(!pinConfigured)
    }
}
