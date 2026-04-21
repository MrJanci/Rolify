import SwiftUI

/// Spotify-style Home. Modular aufgebaut damit Swift-Compiler nicht timeout.
struct HomeView: View {
    @State private var shelves: [HomeShelf] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var api = API.shared
    @State private var player = Player.shared
    @State private var profile: UserProfile?
    @State private var selectedCategory = "Alle"
    @State private var showAddToPlaylist = false
    @State private var pendingTrackId = ""
    @State private var pendingTrackTitle = ""
    @State private var showProfile = false

    private let categories = ["Alle", "Musik", "Podcasts", "Hoerbuecher"]

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()
            contentArea
        }
        .navigationBarHidden(true)
        .navigationDestination(for: PlaylistRoute.self) { playlistDestination($0) }
        .navigationDestination(for: LibraryRoute.self) { libraryDestination($0) }
        .sheet(isPresented: $showProfile) {
            ProfileSheet().presentationDetents([.large])
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(trackId: pendingTrackId, trackTitle: pendingTrackTitle)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task {
            await loadProfile()
            if shelves.isEmpty { await load() }
        }
    }

    // MARK: Routing

    @ViewBuilder
    private func playlistDestination(_ route: PlaylistRoute) -> some View {
        switch route {
        case let .detail(id, name):
            PlaylistDetailView(playlistId: id, initialName: name)
        }
    }

    @ViewBuilder
    private func libraryDestination(_ route: LibraryRoute) -> some View {
        switch route {
        case let .album(id): AlbumDetailView(albumId: id)
        case let .artist(id): ArtistDetailView(artistId: id)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var contentArea: some View {
        if isLoading && shelves.isEmpty {
            ProgressView().tint(DS.accent).frame(maxHeight: .infinity)
        } else if let error {
            ErrorView(message: error) { Task { await load() } }
        } else {
            scrollContent
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar.padding(.bottom, DS.m)
                quickPicksGrid
                    .padding(.horizontal, DS.l)
                    .padding(.top, DS.s)
                mixShelfSection
                jumpBackSection
                Spacer().frame(height: 140)
            }
        }
        .refreshable { await load() }
    }

    // MARK: Top Bar

    private var topBar: some View {
        HStack(spacing: DS.m) {
            AvatarButton(avatarUrl: profile?.avatarUrl,
                         displayName: profile?.displayName ?? "U") {
                showProfile = true
            }
            .padding(.leading, DS.l)

            TopBarPills(options: categories,
                        selection: $selectedCategory,
                        allowDeselect: false)
        }
        .padding(.top, DS.s)
    }

    // MARK: Quick Picks

    @ViewBuilder
    private var quickPicksGrid: some View {
        let tracks = currentTracks
        if !tracks.isEmpty {
            LazyVGrid(columns: gridColumns, spacing: DS.s) {
                ForEach(tracks.prefix(8)) { t in
                    quickPickCell(t, allTracks: tracks)
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: DS.s),
         GridItem(.flexible(), spacing: DS.s)]
    }

    private func quickPickCell(_ t: TrackListItem,
                                allTracks: [TrackListItem]) -> some View {
        QuickPickTile(title: t.title, coverUrl: t.coverUrl) {
            let q = allTracks.map { QueueTrack($0) }
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

    // MARK: Shelves

    private var currentTracks: [TrackListItem] {
        shelves.first(where: { $0.id == "recent" })?.tracks ?? []
    }

    private var currentPlaylists: [PlaylistSummary] {
        shelves.first(where: { $0.id == "playlists" })?.playlists ?? []
    }

    @ViewBuilder
    private var mixShelfSection: some View {
        let tracks = currentTracks
        if !tracks.isEmpty {
            shelfTitle("Deine Top-Mixes")
            topMixesShelf(tracks)
        }
    }

    @ViewBuilder
    private var jumpBackSection: some View {
        let playlists = currentPlaylists
        if !playlists.isEmpty {
            shelfTitle("Weiter hoeren")
            jumpBackShelf(playlists)
        }
    }

    private func shelfTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 22, weight: .black))
            .foregroundStyle(DS.textPrimary)
            .padding(.horizontal, DS.l)
            .padding(.top, DS.xl)
            .padding(.bottom, DS.s)
    }

    private func topMixesShelf(_ tracks: [TrackListItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.m) {
                ForEach(Array(tracks.prefix(6).enumerated()), id: \.element.id) { idx, t in
                    mixCardFor(track: t, index: idx, allTracks: tracks)
                }
            }
            .padding(.horizontal, DS.l)
        }
    }

    private func mixCardFor(track: TrackListItem, index: Int,
                            allTracks: [TrackListItem]) -> some View {
        MixShelfCard(
            title: mixTitle(for: index),
            coverUrl: track.coverUrl,
            subtitle: track.artist,
            accentColor: mixColor(for: index)
        ) {
            let q = allTracks.map { QueueTrack($0) }
            Task { await player.play(queue: q, startingAt: track.id) }
        }
    }

    private func jumpBackShelf(_ playlists: [PlaylistSummary]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.m) {
                ForEach(playlists) { p in
                    jumpBackItem(p)
                }
            }
            .padding(.horizontal, DS.l)
        }
    }

    private func jumpBackItem(_ p: PlaylistSummary) -> some View {
        NavigationLink(value: PlaylistRoute.detail(p.id, p.name)) {
            JumpBackCard(
                coverUrl: p.coverUrl.isEmpty ? nil : p.coverUrl,
                title: p.name
            ) {}
        }
        .buttonStyle(.plain)
    }

    // MARK: Helpers

    private func mixTitle(for idx: Int) -> String {
        let titles = ["Dein Mix", "Hip-Hop Mix", "Pop Mix", "Dance Mix", "Chill Mix", "Rock Mix"]
        return idx < titles.count ? titles[idx] : "Mix \(idx + 1)"
    }

    private func mixColor(for idx: Int) -> Color {
        let colors: [Color] = [
            Color(red: 0.96, green: 0.48, blue: 0.40),
            Color(red: 0.14, green: 0.78, blue: 0.85),
            Color(red: 0.62, green: 0.34, blue: 0.83),
            Color(red: 0.96, green: 0.72, blue: 0.22),
            Color(red: 0.36, green: 0.79, blue: 0.56),
            Color(red: 0.92, green: 0.36, blue: 0.58),
        ]
        return colors[idx % colors.count]
    }

    // MARK: Data

    private func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let home = try await api.browseHome()
            self.shelves = home.shelves ?? []
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadProfile() async {
        if profile != nil { return }
        do { self.profile = try await api.me() } catch { }
    }
}
