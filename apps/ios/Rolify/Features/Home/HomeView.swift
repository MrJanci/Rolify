import SwiftUI

struct HomeView: View {
    @State private var tracks: [TrackListItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var api = API.shared
    @State private var player = Player.shared
    @State private var showAddToPlaylist = false
    @State private var pendingTrackId = ""
    @State private var pendingTrackTitle = ""

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()
            content
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: PlaylistRoute.self) { r in
            switch r { case let .detail(id, name): PlaylistDetailView(playlistId: id, initialName: name) }
        }
        .navigationDestination(for: LibraryRoute.self) { r in
            switch r {
            case let .album(id): AlbumDetailView(albumId: id)
            case let .artist(id): ArtistDetailView(artistId: id)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Text("Home").font(.system(size: 22, weight: .black)).foregroundStyle(DS.textPrimary)
            }
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(trackId: pendingTrackId, trackTitle: pendingTrackTitle)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task { if tracks.isEmpty { await load() } }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && tracks.isEmpty {
            ProgressView().tint(DS.accent).frame(maxHeight: .infinity)
        } else if let error {
            ErrorView(message: error) { Task { await load() } }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(tracks) { t in
                        TrackRow(
                            track: t,
                            isCurrent: player.currentTrack?.trackId == t.id,
                            isPlaying: player.isPlaying && player.currentTrack?.trackId == t.id
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
                        Divider().background(DS.divider).padding(.leading, 88)
                    }
                    Spacer().frame(height: 140)
                }
            }
            .refreshable { await load() }
        }
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
}
