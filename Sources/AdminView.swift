import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct AdminView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var screenTime: ScreenTimeStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("nelly.adminPIN") private var adminPIN = "2468"
    @AppStorage("nelly.theme.dark") private var darkMode = false
    @State private var link = ""
    @State private var message = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showImporter = false
    @State private var newPIN = ""
    @State private var showHistory = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Add a video") {
                    TextField("Paste TikTok, YouTube or video link", text: $link)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Add video link") {
                        do { try library.addLink(link); link = ""; message = "Video added." }
                        catch { message = error.localizedDescription }
                    }.disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    PhotosPicker(selection: $selectedPhoto, matching: .videos) {
                        Label("Choose video from Photos", systemImage: "photo")
                    }
                    Button { showImporter = true } label: {
                        Label("Import video from Files", systemImage: "folder")
                    }
                    if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
                }

                Section("Your video library") {
                    if library.videos.isEmpty { Text("No videos added yet.").foregroundStyle(.secondary) }
                    ForEach(library.videos) { video in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(label(for: video)).font(.subheadline.weight(.medium))
                                Text(video.kind.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("Available", isOn: Binding(
                                get: { video.enabled },
                                set: { value in
                                    if let i = library.videos.firstIndex(where: { $0.id == video.id }) {
                                        library.videos[i].enabled = value
                                    }
                                }
                            )).labelsHidden()
                            Button(role: .destructive) { library.delete(video) } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                    .onMove(perform: library.move)
                }

                Section("Screen time") {
                    Stepper("Daily limit: \(screenTime.dailyLimit) minutes", value: $screenTime.dailyLimit, in: 5...240, step: 5)
                    Text("Remaining today: \(screenTime.remainingSeconds / 60) minutes")
                        .foregroundStyle(.secondary)
                    Button("Reset today's viewing time") { screenTime.resetToday() }
                    Button("Parent override — allow viewing now") { screenTime.parentOverride() }
                }

                Section("Security") {
                    SecureField("New numeric PIN", text: $newPIN).keyboardType(.numberPad)
                    Button("Change PIN") {
                        if newPIN.count >= 4 && newPIN.allSatisfy(\.isNumber) {
                            adminPIN = newPIN; newPIN = ""; message = "PIN changed."
                        } else { message = "PIN must contain at least 4 digits." }
                    }
                    if adminPIN == "2468" {
                        Text("Change the default PIN before giving Nelly to your daughter.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }

                Section("Appearance & history") {
                    Toggle("Dark appearance", isOn: $darkMode)
                    Button("View watch history") { showHistory = true }
                }

                Section {
                    Text("For the strongest child lock, enable Guided Access in iPhone Settings → Accessibility → Guided Access.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Nelly Admin")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.movie, .mpeg4Movie, .video]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    try library.importVideo(data: data, fileName: url.lastPathComponent)
                    message = "Video imported."
                } catch { message = "Could not import video: \(error.localizedDescription)" }
            }
            .onChange(of: selectedPhoto) { _, item in
                Task {
                    guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
                    do {
                        try library.importVideo(data: data, fileName: "Photos-video.mov")
                        message = "Video imported from Photos."
                    } catch { message = error.localizedDescription }
                }
            }
            .sheet(isPresented: $showHistory) {
                NavigationStack {
                    List(library.watchHistory, id: \.self) { entry in
                        Text(URL(string: entry)?.host ?? entry).lineLimit(1)
                    }
                    .navigationTitle("Watch history")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showHistory = false } } }
                }
            }
        }
    }

    private func label(for video: VideoItem) -> String {
        if video.kind == .file { return (video.value as NSString).lastPathComponent }
        return URL(string: video.value)?.host ?? "Video"
    }
}
