import SwiftUI

/// Sheet fuer "zu Playlist hinzufuegen" — wird von .contextMenu auf TrackRow getriggert.
struct AddToPlaylistSheet: View {
    let trackId: String
    let trackTitle: String
    @Environment(\.dismiss) var dismiss

    @State private var playlists: [PlaylistSummary] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var addingTo: String?
    @State private var showCreateNew = false
    @State private var api = API.shared

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if isLoading {
                    ProgressView().tint(DS.accent).frame(maxHeight: .infinity)
                } else if let error {
                    VStack(spacing: DS.m) {
                        Text(error).foregroundStyle(.red).font(DS.Font.caption)
                        Button("Nochmal") { Task { await load() } }.foregroundStyle(DS.accent)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // Neue Playlist erstellen
                            Button { showCreateNew = true } label: {
                                HStack(spacing: DS.m) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: DS.radiusS)
                                            .fill(DS.bgElevated)
                                            .frame(width: 48, height: 48)
                                        Image(systemName: "plus")
                                            .font(.system(size: 20, weight: .bold))
                                            .foregroundStyle(DS.accent)
                                    }
                                    Text("Neue Playlist")
                                        .font(DS.Font.bodyLarge)
                                        .foregroundStyle(DS.textPrimary)
                                    Spacer()
                                }
                                .padding(.horizontal, DS.xl)
                                .padding(.vertical, DS.s)
                            }
                            .buttonStyle(.plain)

                            Divider().background(DS.divider).padding(.leading, 76)

                            // Bestehende Playlists
                            ForEach(playlists) { p in
                                playlistRow(p)
                            }
                            Spacer().frame(height: 40)
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showCreateNew) {
            CreatePlaylistSheet { created in
                playlists.insert(created, at: 0)
                Task { await addToPlaylist(created.id) }
            }
            .presentationDetents([.medium])
        }
        .task { await load() }
    }

    private var header: some View {
        HStack {
            Button("Abbrechen") { dismiss() }
                .foregroundStyle(DS.textSecondary)
            Spacer()
            VStack(spacing: 2) {
                Text("Zu Playlist hinzufuegen")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DS.textPrimary)
                Text(trackTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Color.clear.frame(width: 60)
        }
        .padding(.horizontal, DS.l)
        .padding(.top, DS.l)
        .padding(.bottom, DS.m)
    }

    private func playlistRow(_ p: PlaylistSummary) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await addToPlaylist(p.id) }
        } label: {
            HStack(spacing: DS.m) {
                CoverImage(url: p.coverUrl.isEmpty ? nil : p.coverUrl, cornerRadius: DS.radiusS, placeholder: "music.note.list")
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name)
                        .font(DS.Font.bodyLarge)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text("\(p.trackCount) Tracks")
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.textSecondary)
                }
                Spacer()
                if addingTo == p.id {
                    ProgressView().tint(DS.accent).scaleEffect(0.7)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.textTertiary)
                }
            }
            .padding(.horizontal, DS.xl)
            .padding(.vertical, DS.s)
        }
        .buttonStyle(.plain)
        .disabled(addingTo != nil)
    }

    private func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            self.playlists = try await api.myPlaylists()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func addToPlaylist(_ id: String) async {
        addingTo = id
        defer { addingTo = nil }
        do {
            try await api.addTracksToPlaylist(id, trackIds: [trackId])
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            self.error = error.localizedDescription
        }
    }
}
