import SwiftUI

struct HomeView: View {
    @State private var tracks: [TrackListItem] = []
    @State private var quickAccess: [QuickAccessTile] = []
    @State private var shelves: [HomeShelf] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var api = API.shared
    @State private var player = Player.shared
    @State private var showAddToPlaylist = false
    @State private var pendingTrackId = ""
    @State private var pendingTrackTitle = ""
    @State private var showProfileSheet = false
    @State private var activeFilter: HomeFilter = .all

    enum HomeFilter: String, CaseIterable, Hashable {
        case all = "Alle"
        case music = "Musik"
        case podcasts = "Podcasts"
        case audiobooks = "Hoerbuecher"
        var systemImage: String {
            switch self {
            case .all: return ""
            case .music: return "music.note"
            case .podcasts: return "mic.fill"
            case .audiobooks: return "book.fill"
            }
        }
    }

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

                    // Filter-Pills (Spotify-Pattern: All/Music/Podcasts/Audiobooks)
                    filterPills

                    // Quick-Access-Grid (2x4 kompakte Tiles)
                    if !quickAccess.isEmpty {
                        quickAccessGrid
                    }

                    // Standard Shelves
                    if !shelves.isEmpty {
                        ForEach(shelves) { shelf in
                            shelfView(shelf)
                        }
                    }

                    // Fallback wenn keine Shelves: alle Tracks plain
                    if shelves.isEmpty && !tracks.isEmpty {
                        SectionHeader(title: "Neu hinzugefuegt")
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

    // MARK: - Filter Pills

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HomeFilter.allCases, id: \.self) { f in
                    let isActive = activeFilter == f
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        activeFilter = f
                    } label: {
                        HStack(spacing: 6) {
                            if !f.systemImage.isEmpty {
                                Image(systemName: f.systemImage)
                                    .font(.system(size: 12, weight: .bold))
                            }
                            Text(f.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(isActive ? DS.bg : DS.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(isActive ? DS.accent : DS.bgElevated)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.l)
        }
    }

    // MARK: - Quick-Access-Grid (2x4 Spotify-Style)

    private var quickAccessGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(quickAccess) { tile in
                quickAccessTile(tile)
            }
        }
        .padding(.horizontal, DS.l)
    }

    @ViewBuilder
    private func quickAccessTile(_ tile: QuickAccessTile) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            HStack(spacing: 0) {
                tileCover(tile)
                Text(tile.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 8)
                Spacer(minLength: 0)
            }
            .background(DS.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .frame(height: 56)
        }
        .buttonStyle(.plain)
        .background(quickAccessLink(tile))
    }

    @ViewBuilder
    private func tileCover(_ tile: QuickAccessTile) -> some View {
        if tile.kind == "liked" {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.40, green: 0.20, blue: 0.95),
                        Color(red: 0.95, green: 0.95, blue: 1.0),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Image(systemName: "heart.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)
        } else {
            CoverImage(
                url: tile.coverUrl.isEmpty ? nil : tile.coverUrl,
                cornerRadius: 0,
                placeholder: tile.kind == "playlist" ? "music.note.list" : "square.stack"
            )
            .frame(width: 56, height: 56)
        }
    }

    /// Hidden NavigationLink overlay damit der Quick-Access-Tile auf das richtige Detail navigiert.
    @ViewBuilder
    private func quickAccessLink(_ tile: QuickAccessTile) -> some View {
        switch tile.kind {
        case "liked":
            NavigationLink(value: PlaylistRoute.likedSongs) { Color.clear }.opacity(0)
        case "playlist":
            NavigationLink(value: PlaylistRoute.detail(tile.id, tile.title)) { Color.clear }.opacity(0)
        case "album":
            NavigationLink(value: LibraryRoute.album(tile.id)) { Color.clear }.opacity(0)
        case "artist":
            NavigationLink(value: LibraryRoute.artist(tile.id)) { Color.clear }.opacity(0)
        default:
            EmptyView()
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
            case "stations":
                if let st = shelf.stations { stationsShelfScroll(st) }
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
                        Task {
                            await player.play(
                                queue: q, startingAt: t.id,
                                context: Player.PlayContext(type: "discover", id: nil)
                            )
                        }
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

    /// Recommended-Stations Shelf — Spotify-Style "RADIO"-Card mit 3 face-circles.
    private func stationsShelfScroll(_ items: [StationItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.m) {
                ForEach(items) { s in
                    NavigationLink(value: LibraryRoute.artist(s.id)) {
                        VStack(alignment: .leading, spacing: 6) {
                            ZStack {
                                Color(hex: s.tintHex) ?? DS.bgElevated
                                VStack(alignment: .leading) {
                                    Text("RADIO")
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundStyle(.black.opacity(0.7))
                                        .padding(.top, 8).padding(.leading, 10)
                                    Spacer()
                                    HStack(alignment: .bottom, spacing: -10) {
                                        if !s.coverUrl.isEmpty {
                                            CoverImage(url: s.coverUrl, cornerRadius: 30)
                                                .frame(width: 60, height: 60)
                                                .overlay(Circle().stroke(.white, lineWidth: 2))
                                        }
                                    }
                                    .padding(.leading, 22).padding(.bottom, 12)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                                Text(s.name)
                                    .font(.system(size: 18, weight: .black))
                                    .foregroundStyle(.black)
                                    .lineLimit(2)
                                    .padding(.horizontal, 10)
                                    .padding(.bottom, 10)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            }
                            .frame(width: 148, height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: DS.radiusS))

                            Text(s.subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(DS.textSecondary)
                                .lineLimit(2)
                                .frame(width: 148, alignment: .leading)
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
            Task {
                await player.play(
                    queue: q, startingAt: t.id,
                    context: Player.PlayContext(type: "discover", id: nil)
                )
            }
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
            self.quickAccess = home.quickAccess ?? []
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Color Hex helper

extension Color {
    init?(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard raw.count == 6 || raw.count == 8, let n = UInt64(raw, radix: 16) else { return nil }
        if raw.count == 6 {
            let r = Double((n >> 16) & 0xFF) / 255
            let g = Double((n >> 8) & 0xFF) / 255
            let b = Double(n & 0xFF) / 255
            self = Color(red: r, green: g, blue: b)
        } else {
            let a = Double((n >> 24) & 0xFF) / 255
            let r = Double((n >> 16) & 0xFF) / 255
            let g = Double((n >> 8) & 0xFF) / 255
            let b = Double(n & 0xFF) / 255
            self = Color(red: r, green: g, blue: b).opacity(a)
        }
    }
}
