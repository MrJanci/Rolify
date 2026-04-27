import SwiftUI

enum LibraryFilter: String, CaseIterable, Identifiable {
    case playlists = "Playlists"
    case songs = "Songs"
    case albums = "Alben"
    case artists = "Kuenstler"
    var id: String { rawValue }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case recent = "Kuerzlich"
    case name = "Alphabetisch"
    case creator = "Ersteller"
    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .recent: return "clock"
        case .name: return "textformat"
        case .creator: return "person"
        }
    }
}

struct LibraryView: View {
    @State private var playlists: [PlaylistSummary] = []
    @State private var likedCount: Int = 0
    @State private var savedAlbums: [API.SavedAlbumsResponse.Item] = []
    @State private var savedArtists: [API.SavedArtistsResponse.Item] = []
    @State private var allTracks: [TrackListItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showProfileSheet = false
    @State private var showAddToPlaylist = false
    @State private var pendingTrackId = ""
    @State private var pendingTrackTitle = ""
    @State private var filter: LibraryFilter = .playlists
    @State private var sort: LibrarySort = .recent
    @State private var useGridView: Bool = false
    @State private var api = API.shared
    @State private var player = Player.shared
    @State private var router = CreateRouter.shared

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
                    Text("Deine Bibliothek")
                        .font(DS.Font.title)
                        .foregroundStyle(DS.textPrimary)
                }
            }
            // Plus-Button entfernt — ist jetzt der 4. Tab unten rechts in AppRoot
        }
        .onChange(of: router.showCreateSheet) { oldValue, newValue in
            // Wenn CreateSheet geschlossen wird, reload die Library (evtl. neue Playlist)
            if oldValue && !newValue {
                Task { await load() }
            }
        }
        .sheet(isPresented: $showProfileSheet) {
            ProfileSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(trackId: pendingTrackId, trackTitle: pendingTrackTitle)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task { if playlists.isEmpty && allTracks.isEmpty { await load() } }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && playlists.isEmpty && savedAlbums.isEmpty && savedArtists.isEmpty && allTracks.isEmpty {
            ProgressView().tint(DS.accent).frame(maxHeight: .infinity)
        } else if let error {
            ErrorView(message: error) { Task { await load() } }
        } else {
            VStack(spacing: 0) {
                filterBar
                sortBar
                listView
            }
        }
    }

    // MARK: - Filter Bar (Pills)

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.s) {
                ForEach(LibraryFilter.allCases) { f in
                    pill(title: f.rawValue, isActive: filter == f) {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        withAnimation(.easeInOut(duration: 0.15)) { filter = f }
                    }
                }
            }
            .padding(.horizontal, DS.l)
            .padding(.vertical, DS.s)
        }
    }

    private func pill(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? Color.black : DS.textPrimary)
                .padding(.horizontal, DS.m)
                .padding(.vertical, 7)
                .background(isActive ? DS.textPrimary : DS.bgElevated)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sort Bar

    private var sortBar: some View {
        HStack {
            Menu {
                ForEach(LibrarySort.allCases) { s in
                    Button {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        sort = s
                    } label: {
                        Label(s.rawValue, systemImage: s.iconName)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 11, weight: .bold))
                    Text(sort.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(DS.textPrimary)
            }
            Spacer()
            // Grid/List-Toggle (Spotify-Style)
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(.easeInOut(duration: 0.15)) {
                    useGridView.toggle()
                }
            } label: {
                Image(systemName: useGridView ? "square.grid.2x2" : "list.bullet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.l)
        .padding(.vertical, DS.s)
    }

    // MARK: - List

    @ViewBuilder
    private var listView: some View {
        switch filter {
        case .playlists: playlistList
        case .songs: songsList
        case .albums: albumsList
        case .artists: artistsList
        }
    }

    // MARK: - All Songs (flat)

    private var songsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Liked-Songs row an der Spitze als "Pseudo-Album"
                NavigationLink(value: PlaylistRoute.likedSongs) {
                    likedSongsRow
                }
                .buttonStyle(.plain)
                Divider().background(DS.divider).padding(.leading, 88)

                if allTracks.isEmpty && !isLoading {
                    emptyPlaceholder(title: "Keine Tracks", message: "Scrape Playlists ueber das Profil-Menue, dann tauchen sie hier auf")
                } else {
                    ForEach(allTracks) { t in
                        trackRow(t)
                    }
                }
                Spacer().frame(height: 140)
            }
        }
        .refreshable { await load() }
    }

    private func trackRow(_ t: TrackListItem) -> some View {
        TrackRow(
            track: t,
            isCurrent: player.currentTrack?.trackId == t.id,
            isPlaying: player.isPlaying && player.currentTrack?.trackId == t.id
        ) {
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

    @ViewBuilder
    private var playlistList: some View {
        if useGridView {
            playlistGrid
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Liked-Songs Pseudo-Playlist (ganz oben wie Spotify)
                    NavigationLink(value: PlaylistRoute.likedSongs) {
                        likedSongsRow
                    }
                    .buttonStyle(.plain)
                    Divider().background(DS.divider).padding(.leading, 88)

                    ForEach(sortedPlaylists) { p in
                        NavigationLink(value: PlaylistRoute.detail(p.id, p.name)) {
                            playlistRow(p)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer().frame(height: 140)
                }
            }
            .refreshable { await load() }
        }
    }

    private var playlistGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.m), GridItem(.flexible(), spacing: DS.m)], spacing: DS.m) {
                // Liked-Songs als erstes Grid-Element
                NavigationLink(value: PlaylistRoute.likedSongs) {
                    likedSongsGridTile
                }
                .buttonStyle(.plain)

                ForEach(sortedPlaylists) { p in
                    NavigationLink(value: PlaylistRoute.detail(p.id, p.name)) {
                        playlistGridTile(p)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.l)
            .padding(.top, DS.s)
            Spacer().frame(height: 140)
        }
        .refreshable { await load() }
    }

    private var likedSongsGridTile: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.55, green: 0.20, blue: 0.95), DS.accentDeep],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Image(systemName: "heart.fill")
                    .font(.system(size: 44, weight: .black))
                    .foregroundStyle(.white)
            }
            .aspectRatio(1, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusS))
            Text("Gelikte Songs")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            Text("\(likedCount) Tracks")
                .font(.system(size: 11))
                .foregroundStyle(DS.textSecondary)
        }
    }

    private func playlistGridTile(_ p: PlaylistSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImage(
                url: p.coverUrl.isEmpty ? nil : p.coverUrl,
                cornerRadius: DS.radiusS,
                placeholder: (p.isMixed ?? false) ? "sparkles" : "music.note.list"
            )
            .aspectRatio(1, contentMode: .fill)
            Text(p.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            Text("\(p.trackCount) Tracks")
                .font(.system(size: 11))
                .foregroundStyle(DS.textSecondary)
        }
    }

    private var likedSongsRow: some View {
        HStack(spacing: DS.m) {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.55, green: 0.20, blue: 0.95), DS.accentDeep],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Image(systemName: "heart.fill")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(.white)
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusS))

            VStack(alignment: .leading, spacing: 2) {
                Text("Gelikte Songs")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DS.accent)
                    Text("Playlist · \(likedCount) Tracks")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.textSecondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, DS.l)
        .padding(.vertical, DS.s)
        .contentShape(Rectangle())
    }

    private func playlistRow(_ p: PlaylistSummary) -> some View {
        let isDyn = p.isDynamic ?? false
        return HStack(spacing: DS.m) {
            // Auto-Playlist-Cover: Gradient + sparkles (sonst echtes cover)
            ZStack {
                if isDyn {
                    LinearGradient(
                        colors: [DS.accentBright, DS.accentDeep],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(.white)
                } else {
                    CoverImage(
                        url: p.coverUrl.isEmpty ? nil : p.coverUrl,
                        cornerRadius: DS.radiusS,
                        placeholder: (p.isMixed ?? false) ? "sparkles" : "music.note.list"
                    )
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusS))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(p.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    if isDyn {
                        Image(systemName: "bolt.fill").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(DS.accent)
                    }
                    if p.isCollaborative ?? false {
                        Image(systemName: "person.2.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(DS.accent)
                    }
                    if p.isMixed ?? false {
                        Image(systemName: "sparkles").font(.system(size: 10, weight: .bold)).foregroundStyle(DS.accent)
                    }
                }
                Text(subtitle(for: p))
                    .font(.system(size: 13))
                    .foregroundStyle(DS.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, DS.l)
        .padding(.vertical, DS.s)
        .contentShape(Rectangle())
    }

    private func subtitle(for p: PlaylistSummary) -> String {
        var parts: [String] = []
        if p.isDynamic ?? false { parts.append("Auto") }
        else { parts.append("Playlist") }
        if p.isCollaborative ?? false { parts.append("Kollab") }
        if p.isMixed ?? false { parts.append("Mix") }
        if !(p.isOwned ?? true) && !(p.isDynamic ?? false) { parts.append("geteilt") }
        return parts.joined(separator: " · ") + " · \(p.trackCount) Tracks"
    }

    // MARK: - Saved Albums

    private var albumsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if savedAlbums.isEmpty {
                    emptyPlaceholder(title: "Keine gespeicherten Alben", message: "Speichere Alben ueber das + im Album-Screen")
                } else {
                    ForEach(savedAlbums) { a in
                        NavigationLink(value: LibraryRoute.album(a.id)) {
                            HStack(spacing: DS.m) {
                                CoverImage(url: a.coverUrl, cornerRadius: DS.radiusS)
                                    .frame(width: 56, height: 56)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(a.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(DS.textPrimary)
                                        .lineLimit(1)
                                    Text("Album · \(a.artist)")
                                        .font(.system(size: 13))
                                        .foregroundStyle(DS.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, DS.l)
                            .padding(.vertical, DS.s)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer().frame(height: 140)
            }
        }
        .refreshable { await load() }
    }

    // MARK: - Saved Artists

    private var artistsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if savedArtists.isEmpty {
                    emptyPlaceholder(title: "Noch keine Kuenstler", message: "Folge einem Kuenstler ueber den Button im Artist-Screen")
                } else {
                    ForEach(savedArtists) { a in
                        NavigationLink(value: LibraryRoute.artist(a.id)) {
                            HStack(spacing: DS.m) {
                                CoverImage(url: a.imageUrl, cornerRadius: 28, placeholder: "person.fill")
                                    .frame(width: 56, height: 56)
                                Text(a.name)
                                    .font(DS.Font.bodyLarge)
                                    .foregroundStyle(DS.textPrimary)
                                Spacer()
                                Text("Kuenstler")
                                    .font(.system(size: 12))
                                    .foregroundStyle(DS.textSecondary)
                            }
                            .padding(.horizontal, DS.l)
                            .padding(.vertical, DS.s)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer().frame(height: 140)
            }
        }
        .refreshable { await load() }
    }

    private func emptyPlaceholder(title: String, message: String) -> some View {
        VStack(spacing: DS.s) {
            Spacer().frame(height: 80)
            Image(systemName: "tray")
                .font(.system(size: 44))
                .foregroundStyle(DS.textTertiary)
            Text(title)
                .font(DS.Font.bodyLarge)
                .foregroundStyle(DS.textPrimary)
            Text(message)
                .font(DS.Font.caption)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.xxl)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sort-Logic

    private var sortedPlaylists: [PlaylistSummary] {
        switch sort {
        case .recent: return playlists
        case .name: return playlists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .creator: return playlists
        }
    }

    private func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }

        // Jeden Call einzeln - Partial-Data statt komplettem Screen-Fail wenn eine
        // einzelne Route haengt/cancelt. Pull-to-refresh swallowt Cancellations.
        var hardError: String? = nil

        if let pl = try? await api.myPlaylists() { self.playlists = pl }
        else if !Task.isCancelled { hardError = "Playlists konnten nicht geladen werden" }

        if let liked = try? await api.likedTracks() { self.likedCount = liked.count }
        if let albs = try? await api.savedAlbums() { self.savedAlbums = albs }
        if let arts = try? await api.savedArtists() { self.savedArtists = arts }
        if let tracks = try? await api.allTracks(limit: 300) { self.allTracks = tracks }

        // Error nur setzen wenn Core-Call (playlists) fehlschlaegt UND nicht cancelled
        if let msg = hardError, !Task.isCancelled {
            self.error = msg
        }
    }
}

enum PlaylistRoute: Hashable {
    case detail(String, String?)
    case likedSongs
}

enum LibraryRoute: Hashable {
    case album(String)
    case artist(String)
}
