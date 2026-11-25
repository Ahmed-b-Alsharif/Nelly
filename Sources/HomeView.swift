import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var screenTime: ScreenTimeStore
    @EnvironmentObject private var syncManager: NellySyncManager
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
    @State private var headLoopVideoID: UUID?
    @State private var tailLoopVideoID: UUID?
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
            } else if !screenTime.isTimerRunning {
                waitingForLimitScreen
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
            // Cloud sync must never delay the one-second screen-time clock.
            Task {
                await syncManager.syncNow(library: library, screenTime: screenTime)
            }
            var syncTicks = 0
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    break
                }
                guard scenePhase == .active else { continue }
                if screenTime.isTimerRunning {
                    screenTime.tick()
                }
                syncTicks += 1
                if syncTicks >= 30 {
                    syncTicks = 0
                    Task {
                        await syncManager.syncNow(library: library, screenTime: screenTime)
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                screenTime.setPlaying(false)
            } else {
                prepareRandomPlayback()
                Task { await syncManager.syncNow(library: library, screenTime: screenTime) }
            }
        }
        .onChange(of: library.videos) { _, _ in
            Task { await syncManager.syncNow(library: library, screenTime: screenTime, pushLibraryMetadata: true) }
        }
        .onChange(of: currentVideoID) { _, newID in
            if newID == headLoopVideoID {
                // The duplicate first page at the top represents the last real video.
                currentVideoID = playbackVideos.last?.id
                return
            }
            if newID == tailLoopVideoID {
                // The duplicate last page at the bottom represents the first real video.
                currentVideoID = playbackVideos.first?.id
                return
            }
            if let item = playbackVideos.first(where: { $0.id == newID }) {
                library.recordWatch(item)
            }
        }
        .onChange(of: library.activeVideos) { _, active in
            if !active.contains(where: { $0.id == currentVideoID }) {
                currentVideoID = active.first?.id
            }
        }
    }

    private var feedVideos: [VideoItem] {
        guard let first = playbackVideos.first, let last = playbackVideos.last,
              let headID = headLoopVideoID, let tailID = tailLoopVideoID else { return playbackVideos }
        var headCopy = last
        headCopy.id = headID
        var tailCopy = first
        tailCopy.id = tailID
        return [headCopy] + playbackVideos + [tailCopy]
    }

    private var feed: some View {
        GeometryReader { geo in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(feedVideos) { item in
                        ZStack {
                            VideoPlayerView(item: item, isPlaying: screenTime.isPlaying && currentVideoID == item.id && scenePhase == .active && !showAdmin && !showPIN)
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
        if playbackVideos.isEmpty { prepareRandomPlayback(); return }
        if currentVideoID == nil { currentVideoID = playbackVideos.first?.id }
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
        headLoopVideoID = playbackVideos.first.map { _ in UUID() }
        tailLoopVideoID = playbackVideos.first.map { _ in UUID() }
        currentVideoID = playbackVideos.first?.id
        screenTime.setPlaying(!screenTime.isLimitReached)
    }

    private func resetFeedToBeginning() {
        if playbackVideos.isEmpty { prepareRandomPlayback(); return }
        currentVideoID = playbackVideos.first?.id
        screenTime.setPlaying(!screenTime.isLimitReached)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "butterfly.fill").font(.system(size: 70)).foregroundStyle(.pink)
            Text("Nelly").font(.largeTitle.bold()).foregroundStyle(.white)
            Text("Your videos will be here").foregroundStyle(.white.opacity(0.7))
        }
    }

    private var waitingForLimitScreen: some View {
        VStack(spacing: 18) {
            Image(systemName: "timer")
                .font(.system(size: 62, weight: .light))
                .foregroundStyle(.white)
            Text("Ready when you are!")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Ask a parent to choose your screen time and press Confirm.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [Color.purple, Color.pink.opacity(0.85), Color.purple],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private var limitScreen: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.30, green: 0.10, blue: 0.72),
                             Color(red: 0.60, green: 0.18, blue: 0.96),
                             Color(red: 0.22, green: 0.08, blue: 0.55)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Circle()
                    .fill(Color.pink.opacity(0.82))
                    .frame(width: geometry.size.width * 1.35)
                    .offset(y: -geometry.size.height * 0.12)
                ForEach(0..<18, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3)
                        .fill([Color.yellow, Color.cyan, Color.mint, Color.pink][index % 4])
                        .frame(width: 13, height: 34)
                        .rotationEffect(.degrees(Double(index * 29)))
                        .position(
                            x: CGFloat((index * 73 + 31) % max(1, Int(geometry.size.width))),
                            y: CGFloat((index * 97 + 55) % max(1, Int(geometry.size.height * 0.55)))
                        )
                }

                VStack(spacing: 18) {
                    Spacer(minLength: 36)
                    Text("NELLY")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .tracking(5)
                        .foregroundStyle(.white.opacity(0.9))

                    HStack(spacing: 16) {
                        Text("🎸").font(.system(size: 58))
                        Text("🎤").font(.system(size: 66))
                        Text("🥁").font(.system(size: 58))
                    }
                    .padding(.vertical, 22)
                    .frame(maxWidth: .infinity)
                    .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 28))
                    .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.28), lineWidth: 2))

                    Image(systemName: "clock.fill")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.top, 8)
                    Text("Time’s up!")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("That’s all the screen time for today.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)

                    Spacer(minLength: 8)

                    VStack(spacing: 12) {
                        Text("Ask a parent to unlock more time")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        SecureField("Parent PIN", text: $limitPIN)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 260)
                            .multilineTextAlignment(.center)
                        if !limitPINError.isEmpty {
                            Text(limitPINError).font(.caption).foregroundStyle(.yellow)
                        }
                        Button {
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
                        } label: {
                            Text("Parent unlock")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.purple)
                                .frame(maxWidth: 260)
                                .padding(.vertical, 13)
                                .background(.white, in: Capsule())
                        }
                        .disabled(!pinConfigured || limitPIN.isEmpty)
                        Text("Nelly will be ready when a parent approves more time.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 24))
                    .padding(.bottom, 18)
                }
                .padding(.horizontal, 22)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .ignoresSafeArea()
        }
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
