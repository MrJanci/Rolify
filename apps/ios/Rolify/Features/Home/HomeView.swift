import SwiftUI

struct HomeView: View {
    @State private var tracks: [TrackListItem] = []
    @State private var shelves: [HomeShelf] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var api = API.shared
    @State private var player = Player.shared
    @State private var showAddToPlaylist = false
    @State private var pendingTrackId = ""
    @State private var pendingTrackTitle = ""
    @State private var showProfileSheet = false

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()
            content
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: PlaylistRoute.self) { r in
            switch r {
            case let .detail(id, name): PlaylistDetailView(playlistId: id, initialName: name)
            case .likedSongs: LikedSongsView()
            }
        }
        .navigationDestination(for: LibraryRoute.self) { r in
            switch r {
            case let .album(id): AlbumDetailView(albumId: id)
            case let .artist(id): ArtistDetailView(artistId: id)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: DS.m) {
                    AvatarButton { showProfileSheet = true }
                    Text(greeting)
                        .font(DS.Font.title)
                        .foregroundStyle(DS.textPrimary)
                }
            }
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(trackId: pendingTrackId, trackTitle: pendingTrackTitle)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showProfileSheet) {
            ProfileSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task { if tracks.isEmpty && shelves.isEmpty { await load() } }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Guten Morgen"
        case 12..<18: return "Guten Nachmittag"
        default: return "Guten Abend"
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && tracks.isEmpty && shelves.isEmpty {
            ProgressView().tint(DS.accent).frame(maxHeight: .infinity)
        } else if let error {
            ErrorView(message: error) { Task { await load() } }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.l) {
                    Spacer().frame(height: DS.s)

                    // Shelves-Mode (wenn Backend welche liefert)
                    if !shelves.isEmpty {
                        ForEach(shelves) { shelf in
                            shelfView(shelf)
                        }
                    }

                    // Fallback: "Neu hinzugefuegt"-Tracks als Plain-Liste
                    if !tracks.isEmpty {
                        SectionHeader(title: shelves.isEmpty ? "Neu hinzugefuegt" : "Alle Tracks")
                        ForEach(tracks) { t in
                            trackRowWithMenu(t)
                            Divider().background(DS.divider).padding(.leading, 88)
                        }
                    }

                    Spacer().frame(height: 140)
                }
            }
            .refreshable { await load() }
        }
    }

    // MARK: - Shelf

    @ViewBuilder
    private func shelfView(_ shelf: HomeShelf) -> some View {
        VStack(alignment: .leading, spacing: DS.s) {
            Text(shelf.title)
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(DS.textPrimary)
                .padding(.horizontal, DS.l)

            switch shelf.kind {
            case "tracks":
                if let ts = shelf.tracks { tracksShelfScroll(ts) }
            case "playlists":
                if let ps = shelf.playlists { playlistsShelfScroll(ps) }
            case "albums":
                if let albs = shelf.albums { albumsShelfScroll(albs) }
            default:
                EmptyView()
            }
        }
    }

    private func tracksShelfScroll(_ items: [TrackListItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.m) {
                ForEach(items) { t in
                    Button {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        let q = items.map { QueueTrack($0) }
                        Task { await player.play(queue: q, startingAt: t.id) }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            CoverImage(url: t.coverUrl, cornerRadius: DS.radiusS)
                                .frame(width: 148, height: 148)
                            Text(t.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(DS.textPrimary)
                                .lineLimit(1)
                                .frame(width: 148, alignment: .leading)
                            Text(t.artist)
                                .font(.system(size: 11))
                                .foregroundStyle(DS.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.l)
        }
    }

    private func playlistsShelfScroll(_ items: [PlaylistSummary]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.m) {
                ForEach(items) { p in
                    NavigationLink(value: PlaylistRoute.detail(p.id, p.name)) {
                        VStack(alignment: .leading, spacing: 6) {
                            CoverImage(
                                url: p.coverUrl.isEmpty ? nil : p.coverUrl,
                                cornerRadius: DS.radiusS,
                                placeholder: "music.note.list"
                            )
                            .frame(width: 148, height: 148)
                            Text(p.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(DS.textPrimary)
                                .lineLimit(1)
                                .frame(width: 148, alignment: .leading)
                            Text("\(p.trackCount) Tracks")
                                .font(.system(size: 11))
                                .foregroundStyle(DS.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.l)
        }
    }

    private func albumsShelfScroll(_ items: [AlbumListItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.m) {
                ForEach(items) { a in
                    NavigationLink(value: LibraryRoute.album(a.id)) {
                        VStack(alignment: .leading, spacing: 6) {
                            CoverImage(url: a.coverUrl, cornerRadius: DS.radiusS)
                                .frame(width: 148, height: 148)
                            Text(a.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(DS.textPrimary)
                                .lineLimit(1)
                                .frame(width: 148, alignment: .leading)
                            Text(a.artist)
                                .font(.system(size: 11))
                                .foregroundStyle(DS.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.l)
        }
    }

    // MARK: - Plain tracks row

    private func trackRowWithMenu(_ t: TrackListItem) -> some View {
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
    }

    private func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let home = try await api.browseHome()
            self.tracks = home.tracks
            self.shelves = home.shelves ?? []
        } catch {
            self.error = error.localizedDescription
        }
    }
}
