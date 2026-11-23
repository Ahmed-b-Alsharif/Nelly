import SwiftUI
import UIKit
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
    @State private var editingVideo: VideoItem?

    var body: some View {
        NavigationStack {
            Form {
                Section("Add a TikTok video") {
                    TextField("Paste TikTok video link", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        if let copied = UIPasteboard.general.string { link = copied }
                        else { message = "Copy a TikTok link first, then tap Paste link." }
                    } label: {
                        Label("Paste copied link", systemImage: "doc.on.clipboard")
                    }
                    Button {
                        let value = link.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard let url = URL(string: value),
                              url.host?.lowercased().contains("tiktok.com") == true,
                              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                            message = "Please paste a valid TikTok link."
                            return
                        }
                        message = "TikTok does not provide Nelly with an official direct-download service for ordinary video links. In TikTok, use Share → Save Video (if available), then import it below. Nelly will keep the saved copy offline."
                    } label: {
                        Label("Check TikTok link", systemImage: "arrow.down.circle")
                    }
                    .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("For safety and reliability, Nelly won't scrape TikTok or use unofficial download services. A copied TikTok link alone cannot be guaranteed to provide the video file.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    PhotosPicker(selection: $selectedPhoto, matching: .videos) {
                        Label("Import saved video from Photos", systemImage: "photo")
                    }
                    Button { showImporter = true } label: {
                        Label("Import video from Files", systemImage: "folder")
                    }
                    if !message.isEmpty {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Your video library") {
                    if library.videos.isEmpty {
                        Text("No videos added yet.").foregroundStyle(.secondary)
                    }
                    ForEach(library.videos) { video in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(label(for: video)).font(.subheadline.weight(.medium))
                                Text(video.kind.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { editingVideo = video } label: {
                                Image(systemName: "pencil")
                            }
                            Toggle("Available", isOn: Binding(
                                get: { video.enabled },
                                set: { value in
                                    if let i = library.videos.firstIndex(where: { $0.id == video.id }) {
                                        library.videos[i].enabled = value
                                    }
                                }
                            ))
                            .labelsHidden()
                            Button(role: .destructive) {
                                library.delete(video)
                            } label: {
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
                            adminPIN = newPIN
                            newPIN = ""
                            message = "PIN changed."
                        } else {
                            message = "PIN must contain at least 4 digits."
                        }
                    }
                    if adminPIN == "2468" {
                        Text("Change the default PIN before giving Nelly to your daughter.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Appearance & history") {
                    Toggle("Dark appearance", isOn: $darkMode)
                    Button("View watch history") { showHistory = true }
                }

                Section {
                    Text("For the strongest child lock, enable Guided Access in iPhone Settings → Accessibility → Guided Access.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                } catch {
                    message = "Could not import video: \(error.localizedDescription)"
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                Task {
                    guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
                    do {
                        try library.importVideo(data: data, fileName: "Photos-video.mov")
                        message = "Video imported from Photos."
                    } catch {
                        message = error.localizedDescription
                    }
                }
            }
            .sheet(item: $editingVideo) { video in
                VideoEditorView(video: video)
            }
            .sheet(isPresented: $showHistory) {
                NavigationStack {
                    List(library.watchHistory, id: \.self) { entry in
                        Text(URL(string: entry)?.host ?? entry).lineLimit(1)
                    }
                    .navigationTitle("Watch history")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showHistory = false }
                        }
                    }
                }
            }
        }
    }

    private func label(for video: VideoItem) -> String {
        if let title = video.title, !title.isEmpty { return title }
        if video.kind == .file { return (video.value as NSString).lastPathComponent }
        return URL(string: video.value)?.host ?? "Video"
    }
}

private struct VideoEditorView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let video: VideoItem
    @State private var value: String
    @State private var title: String
    @State private var errorMessage = ""

    init(video: VideoItem) {
        self.video = video
        _value = State(initialValue: video.value)
        _title = State(initialValue: video.title ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if video.kind != .file {
                    Section("Video link") {
                        TextField("Video URL", text: $value)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                }
                Section("Private admin details") {
                    TextField("Optional title", text: $title)
                }
                if !errorMessage.isEmpty {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Edit video")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try library.update(video, value: value, title: title)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
        }
    }
}
