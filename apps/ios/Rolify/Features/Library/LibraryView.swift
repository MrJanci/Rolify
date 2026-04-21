import SwiftUI

/// Spotify-style "Your Library" Screen:
///   [Avatar] Deine Bibliothek                     [Search] [+]
///   [Playlists] [Alben] [Kuenstler] [Heruntergeladen]
///   [sort-icon] Zuletzt ...................... [grid-toggle]
///   [playlist-row 1]
///   [playlist-row 2]
///   ...
struct LibraryView: View {
    @State private var tracks: [TrackListItem] = []
    @State private var playlists: [PlaylistSummary] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedFilter = ""
    @State private var showCreateSheet = false
    @State private var showCreatePlaylist = false
    @State private var showProfile = false
    @State private var showAddToPlaylist = false
    @State private var pendingTrackId = ""
    @State private var pendingTrackTitle = ""
    @State private var isGridMode = false
    @State private var api = API.shared
    @State private var player = Player.shared
    @State private var profile: UserProfile?

    private let filterOptions = ["Playlists", "Alben", "Kuenstler", "Heruntergeladen"]

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            if isLoading && playlists.isEmpty && tracks.isEmpty {
                ProgressView().tint(DS.accent).frame(maxHeight: .infinity)
            } else if let error {
                ErrorView(message: error) { Task { await load() } }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        topHeader
                        filterPills
                            .padding(.top, DS.m)
                        sortToggleRow
                            .padding(.vertical, DS.m)

                        ForEach(displayedPlaylists) { p in
                            NavigationLink(value: PlaylistRoute.detail(p.id, p.name)) {
                                playlistRowContent(p)
                            }
                            .buttonStyle(.plain)
                        }

                        if displayedPlaylists.isEmpty && tracks.isEmpty {
                            emptyState
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
            ProfileSheet().presentationDetents([.large])
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateSheet(showCreatePlaylist: $showCreatePlaylist)
                .presentationDetents([.height(540)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCreatePlaylist) {
            CreatePlaylistSheet { created in
                playlists.insert(created, at: 0)
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(trackId: pendingTrackId, trackTitle: pendingTrackTitle)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task {
            await loadProfile()
            if playlists.isEmpty && tracks.isEmpty { await load() }
        }
    }

    // MARK: Header

    private var topHeader: some View {
        HStack(spacing: DS.m) {
            AvatarButton(avatarUrl: profile?.avatarUrl, displayName: profile?.displayName ?? "U") {
                showProfile = true
            }
            Text("Deine Bibliothek")
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(DS.textPrimary)

            Spacer()

            Button { } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(DS.textPrimary)
            }
            .buttonStyle(.plain)

            Button {
                showCreateSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(DS.textPrimary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.l)
        .padding(.top, DS.s)
    }

    private var filterPills: some View {
        TopBarPills(options: filterOptions, selection: $selectedFilter, allowDeselect: true)
    }

    private var sortToggleRow: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: DS.xs) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Zuletzt")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(DS.textPrimary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isGridMode.toggle()
            } label: {
                Image(systemName: isGridMode ? "list.bullet" : "square.grid.2x2")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.textPrimary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.l)
    }

    // MARK: Rows

    private var displayedPlaylists: [PlaylistSummary] {
        if selectedFilter.isEmpty || selectedFilter == "Playlists" || selectedFilter == "Heruntergeladen" {
            return playlists
        }
        return []
    }

    private func playlistRowContent(_ p: PlaylistSummary) -> some View {
        HStack(spacing: DS.m) {
            CoverImage(
                url: p.coverUrl.isEmpty ? nil : p.coverUrl,
                cornerRadius: DS.radiusS,
                placeholder: "music.note.list"
            )
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(p.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.accent)
                    Text("Playlist")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.textSecondary)
                    if p.trackCount > 0 {
                        Text("·")
                            .foregroundStyle(DS.textSecondary)
                        Text("\(p.trackCount) Tracks")
                            .font(.system(size: 13))
                            .foregroundStyle(DS.textSecondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, DS.l)
        .padding(.vertical, DS.s)
    }

    private var emptyState: some View {
        VStack(spacing: DS.m) {
            Spacer().frame(height: 80)
            Image(systemName: "books.vertical")
                .font(.system(size: 40))
                .foregroundStyle(DS.textSecondary)
            Text("Noch nichts hier")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DS.textPrimary)
            Text("Erstelle deine erste Playlist")
                .font(.system(size: 14))
                .foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Data

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

    private func loadProfile() async {
        if profile != nil { return }
        do { self.profile = try await api.me() } catch { }
    }
}

enum PlaylistRoute: Hashable {
    case detail(String, String?)
}

enum LibraryRoute: Hashable {
    case album(String)
    case artist(String)
}
