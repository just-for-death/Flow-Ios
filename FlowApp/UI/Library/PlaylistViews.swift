import SwiftUI

// MARK: - SaveToPlaylistSheet
struct SaveToPlaylistSheet: View {
    let video: VideoItem
    let durationSeconds: Int64

    @Environment(\.dismiss) private var dismiss
    @Environment(FlowDatabase.self) private var db
    @State private var newTitle = ""
    @State private var showCreate = false

    private var playlists: [CanonicalPlaylist] { db.userPlaylists() }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showCreate = true
                    } label: {
                        Label("New playlist", systemImage: "plus.circle")
                    }
                }

                Section("Your playlists") {
                    if playlists.isEmpty {
                        Text("No playlists yet")
                            .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                    } else {
                        ForEach(playlists, id: \.syncId) { pl in
                            Button {
                                save(to: pl.syncId)
                            } label: {
                                HStack {
                                    Text(pl.title)
                                    Spacer()
                                    Text("\(pl.items.count)")
                                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                                }
                            }
                            .foregroundStyle(FlowTheme.Colors.onSurface)
                        }
                    }
                }
            }
            .navigationTitle("Save to playlist")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("New playlist", isPresented: $showCreate) {
                TextField("Name", text: $newTitle)
                Button("Create") {
                    let pl = db.createPlaylist(title: newTitle)
                    newTitle = ""
                    save(to: pl.syncId)
                }
                Button("Cancel", role: .cancel) { newTitle = "" }
            }
        }
    }

    private func save(to syncId: String) {
        let item = CanonicalPlaylistItem(
            videoId: video.id,
            addedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            title: video.title,
            channelName: video.channelName,
            channelId: video.channelID,
            thumbnailUrl: video.thumbnailURL?.absoluteString ?? "",
            durationSeconds: durationSeconds,
            hlc: SyncHLC.now()
        )
        db.addToPlaylist(syncId: syncId, item: item)
        dismiss()
    }
}

// MARK: - CreatePlaylistSheet
struct CreatePlaylistSheet: View {
    @Binding var isPresented: Bool
    @Environment(FlowDatabase.self) private var db
    @State private var title = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Playlist name", text: $title)
            }
            .navigationTitle("New Playlist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false; title = "" }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        _ = db.createPlaylist(title: title)
                        isPresented = false
                        title = ""
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
