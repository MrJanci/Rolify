import SwiftUI

/// Minimale HomeView - Fallback-Version um Compile zum Laufen zu bringen.
/// Wenn das build, fuegen wir iterativ Features wieder hinzu.
struct HomeView: View {
    @State private var tracks: [TrackListItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var api = API.shared
    @State private var player = Player.shared
    @State private var profile: UserProfile?
    @State private var showProfile = false
    @State private var showAddToPlaylist = false
    @State private var pendingTrackId = ""
    @State private var pendingTrackTitle = ""

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()
            mainContent
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: PlaylistRoute.self) { playlistRoute($0) }
        .navigationDestination(for: LibraryRoute.self) { libraryRoute($0) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                AvatarButton(
                    avatarUrl: profile?.avatarUrl,
                    displayName: profile?.displayName ?? "U"
                ) { showProfile = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Text("Home")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(DS.textPrimary)
            }
        }
        .sheet(isPresented: $showProfile) {
            ProfileSheet().presentationDetents([.large])
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(
                trackId: pendingTrackId,
                trackTitle: pendingTrackTitle
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .task {
            await loadProfile()
            if tracks.isEmpty { await load() }
        }
    }

    @ViewBuilder
    private func playlistRoute(_ route: PlaylistRoute) -> some View {
        switch route {
        case let .detail(id, name):
            PlaylistDetailView(playlistId: id, initialName: name)
        }
    }

    @ViewBuilder
    private func libraryRoute(_ route: LibraryRoute) -> some View {
        switch route {
        case let .album(id): AlbumDetailView(albumId: id)
        case let .artist(id): ArtistDetailView(artistId: id)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if isLoading && tracks.isEmpty {
            ProgressView().tint(DS.accent).frame(maxHeight: .infinity)
        } else if let error {
            ErrorView(message: error) { Task { await load() } }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(tracks) { t in
                        trackRow(t)
                        Divider().background(DS.divider).padding(.leading, 88)
                    }
                    Spacer().frame(height: 140)
                }
            }
            .refreshable { await load() }
        }
    }

    private func trackRow(_ t: TrackListItem) -> some View {
        let isCurrent = player.currentTrack?.trackId == t.id
        let isPlaying = player.isPlaying && isCurrent
        return TrackRow(
            track: t,
            isCurrent: isCurrent,
            isPlaying: isPlaying
        ) {
            let q = tracks.map { QueueTrack($0) }
            Task { await player.play(queue: q, startingAt: t.id) }
        }
        .rolifyTrackContextMenu(
            queueTrack: QueueTrack(t),
            albumId: t.albumId,
            showAddToPlaylist: $showAddToPlaylist,
            pendingTrackId: $pendingTrackId,
            pendingTrackTitle: $pendingTrackTitle
        )
    }

    private func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let home = try await api.browseHome()
            self.tracks = home.tracks
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadProfile() async {
        if profile != nil { return }
        do { self.profile = try await api.me() } catch { }
    }
}
