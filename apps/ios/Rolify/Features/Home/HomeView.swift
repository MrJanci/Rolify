import SwiftUI

/// Spotify-style Home. 1:1 Layout:
///   [Avatar] [All] [Musik] [Podcasts] [Hoerbuecher]   (Top-Bar)
///   [QuickPickTile x8 in 2-col grid]
///   "Deine Top-Mixes" -> horizontal MixShelfCard Shelf
///   "Weiter hoeren" -> horizontal JumpBackCard Shelf
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

            if isLoading && shelves.isEmpty {
                ProgressView().tint(DS.accent).frame(maxHeight: .infinity)
            } else if let error {
                ErrorView(message: error) { Task { await load() } }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        topBar
                            .padding(.bottom, DS.m)

                        quickPicksGrid
                            .padding(.horizontal, DS.l)
                            .padding(.top, DS.s)

                        if let mixShelf = shelves.first(where: { $0.id == "recent" && ($0.tracks?.count ?? 0) > 0 }) {
                            shelfTitle("Deine Top-Mixes")
                            topMixesShelf(mixShelf)
                        }

                        if let playlistShelf = shelves.first(where: { $0.id == "playlists" && ($0.playlists?.count ?? 0) > 0 }) {
                            shelfTitle("Weiter hoeren")
                            jumpBackShelf(playlistShelf)
                        }

                        Spacer().frame(height: 140)
                    }
                }
                .refreshable { await load() }
            }
        }
        .navigationBarHidden(true)
        .navigationDestination(for: PlaylistRoute.self) { route in
            switch route {
            case let .detail(id, name): PlaylistDetailView(playlistId: id, initialName: name)
            }
        }
        .navigationDestination(for: LibraryRoute.self) { route in
            switch route {
            case let .album(id): AlbumDetailView(albumId: id)
            case let .artist(id): ArtistDetailView(artistId: id)
            }
        }
        .sheet(isPresented: $showProfile) {
            ProfileSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
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

    // MARK: Top-Bar (Avatar + Pills)

    private var topBar: some View {
        HStack(spacing: DS.m) {
            AvatarButton(avatarUrl: profile?.avatarUrl, displayName: profile?.displayName ?? "U") {
                showProfile = true
            }
            .padding(.leading, DS.l)

            TopBarPills(options: categories, selection: $selectedCategory, allowDeselect: false)
        }
        .padding(.top, DS.s)
    }

    // MARK: Quick-Picks-Grid (2 cols x 4 rows)

    @ViewBuilder
    private var quickPicksGrid: some View {
        let tracks = shelves.first(where: { $0.id == "recent" })?.tracks ?? []
        if !tracks.isEmpty {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: DS.s),
                GridItem(.flexible(), spacing: DS.s),
            ], spacing: DS.s) {
                ForEach(tracks.prefix(8)) { t in
                    QuickPickTile(title: t.title, coverUrl: t.coverUrl) {
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
            }
        }
    }

    // MARK: Shelves

    private func shelfTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 22, weight: .black))
            .foregroundStyle(DS.textPrimary)
            .padding(.horizontal, DS.l)
            .padding(.top, DS.xl)
            .padding(.bottom, DS.s)
    }

    private func topMixesShelf(_ shelf: HomeShelf) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.m) {
                let tracks = shelf.tracks ?? []
                ForEach(Array(tracks.prefix(6).enumerated()), id: \.element.id) { idx, t in
                    MixShelfCard(
                        title: mixTitle(for: idx),
                        coverUrl: t.coverUrl,
                        subtitle: t.artist,
                        accentColor: mixColor(for: idx)
                    ) {
                        let q = tracks.map { QueueTrack($0) }
                        Task { await player.play(queue: q, startingAt: t.id) }
                    }
                }
            }
            .padding(.horizontal, DS.l)
        }
    }

    private func jumpBackShelf(_ shelf: HomeShelf) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.m) {
                if let playlists = shelf.playlists {
                    ForEach(playlists) { p in
                        NavigationLink(value: PlaylistRoute.detail(p.id, p.name)) {
                            JumpBackCard(
                                coverUrl: p.coverUrl.isEmpty ? nil : p.coverUrl,
                                title: p.name
                            ) {}
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, DS.l)
        }
    }

    private func mixTitle(for idx: Int) -> String {
        ["Dein Mix", "Hip-Hop Mix", "Pop Mix", "Dance Mix", "Chill Mix", "Rock Mix"][safe: idx] ?? "Mix \(idx + 1)"
    }

    private func mixColor(for idx: Int) -> Color {
        let colors: [Color] = [
            Color(red: 0.96, green: 0.48, blue: 0.40),  // coral
            Color(red: 0.14, green: 0.78, blue: 0.85),  // cyan
            Color(red: 0.62, green: 0.34, blue: 0.83),  // purple
            Color(red: 0.96, green: 0.72, blue: 0.22),  // gold
            Color(red: 0.36, green: 0.79, blue: 0.56),  // teal
            Color(red: 0.92, green: 0.36, blue: 0.58),  // pink
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

// MARK: - Safe-index helper (nur hier, global)

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
