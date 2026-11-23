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

    private var isLockedOut: Bool { Date().timeIntervalSince1970 < lockedUntil }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if library.activeVideos.isEmpty {
                emptyState
            } else if screenTime.isLimitReached {
                limitScreen
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
            if phase != .active { screenTime.setPlaying(false) }
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
                            VideoPlayerView(item: item, isPlaying: screenTime.isPlaying && currentVideoID == item.id && scenePhase == .active)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                screenTime.setPlaying(!screenTime.isPlaying)
                            }
                        }
                        .containerRelativeFrame(.vertical)
                        .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $currentVideoID)
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .onAppear { if currentVideoID == nil { currentVideoID = library.activeVideos.first?.id } }
        }
        .ignoresSafeArea()
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
        }
        .foregroundStyle(.white)
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
