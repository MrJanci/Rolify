import SwiftUI

/// Library zeigt Tracks + Playlists. In Chunk 12 werden das separate Tabs;
/// fuer jetzt ist's eine Single-Page mit zwei Sections.
struct LibraryView: View {
    @State private var tracks: [TrackListItem] = []
    @State private var playlists: [PlaylistSummary] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showCreateSheet = false
    @State private var api = API.shared
    @State private var player = Player.shared

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            if isLoading {
                ProgressView().tint(DS.accent).frame(maxHeight: .infinity)
            } else if let error {
                ErrorView(message: error) { Task { await load() } }
            } else if tracks.isEmpty && playlists.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !playlists.isEmpty {
                            SectionHeader(title: "Deine Playlists")
                            ForEach(playlists) { p in
                                NavigationLink(value: PlaylistRoute.detail(p.id, p.name)) {
                                    playlistRow(p)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        SectionHeader(title: "Alle Tracks")
                        ForEach(tracks) { t in
                            TrackRow(
                                track: t,
                                isCurrent: player.currentTrack?.trackId == t.id,
                                isPlaying: player.isPlaying && player.currentTrack?.trackId == t.id
                            ) {
                                Task { await player.play(trackId: t.id) }
                            }
                            Divider().background(DS.divider).padding(.leading, 88)
                        }
                        Spacer().frame(height: 120)
                    }
                }
                .refreshable { await load() }
            }
        }
        .navigationDestination(for: PlaylistRoute.self) { route in
            switch route {
            case let .detail(id, name):
                PlaylistDetailView(playlistId: id, initialName: name)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bibliothek")
                        .font(DS.Font.headline)
                        .foregroundStyle(DS.textPrimary)
                    Text("\(tracks.count) Tracks · \(playlists.count) Playlists")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.textSecondary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreateSheet = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DS.textPrimary)
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreatePlaylistSheet { created in
                playlists.insert(created, at: 0)
            }
            .presentationDetents([.medium])
        }
        .task { if tracks.isEmpty { await load() } }
    }

    private func playlistRow(_ p: PlaylistSummary) -> some View {
        HStack(spacing: DS.m) {
            CoverImage(url: p.coverUrl.isEmpty ? nil : p.coverUrl, cornerRadius: DS.radiusS, placeholder: "music.note.list")
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name)
                    .font(DS.Font.bodyLarge)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Text("\(p.trackCount) Tracks")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DS.textTertiary)
        }
        .padding(.horizontal, DS.xl)
        .padding(.vertical, DS.s)
    }

    private var emptyState: some View {
        VStack(spacing: DS.m) {
            Image(systemName: "music.note.list")
                .font(.system(size: 44))
                .foregroundStyle(DS.textSecondary)
            Text("Keine Tracks, keine Playlists")
                .font(DS.Font.body)
                .foregroundStyle(DS.textSecondary)
        }
        .frame(maxHeight: .infinity)
    }

    private func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        async let tracksReq = api.browseHome()
        async let playlistsReq = api.myPlaylists()
        do {
            let (home, pls) = try await (tracksReq, playlistsReq)
            self.tracks = home.tracks
            self.playlists = pls
        } catch {
            self.error = error.localizedDescription
        }
    }
}

enum PlaylistRoute: Hashable {
    case detail(String, String?)
}

// MARK: Create Playlist sheet

struct CreatePlaylistSheet: View {
    let onCreated: (PlaylistSummary) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var api = API.shared

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()
            VStack(spacing: DS.l) {
                Text("Neue Playlist")
                    .font(DS.Font.title)
                    .foregroundStyle(DS.textPrimary)
                    .padding(.top, DS.xl)

                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .foregroundStyle(DS.textPrimary)
                    .padding(.horizontal, DS.l)
                    .frame(height: 52)
                    .background(DS.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous))
                    .padding(.horizontal, DS.xl)

                if let error {
                    Text(error)
                        .font(DS.Font.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await create() }
                } label: {
                    HStack {
                        if isLoading { ProgressView().tint(.black).scaleEffect(0.85) }
                        Text("Erstellen").font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(DS.accent)
                    .clipShape(Capsule())
                }
                .disabled(isLoading || name.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, DS.xl)

                Spacer()
            }
        }
    }

    private func create() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let p = try await api.createPlaylist(name: name.trimmingCharacters(in: .whitespaces))
            onCreated(p)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
