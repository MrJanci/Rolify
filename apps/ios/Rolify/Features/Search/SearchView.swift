import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var results: SearchResponse?
    @State private var isLoading = false
    @State private var error: String?
    @State private var debounceTask: Task<Void, Never>?
    @State private var showAddToPlaylist = false
    @State private var pendingTrackId = ""
    @State private var pendingTrackTitle = ""
    @State private var showProfileSheet = false
    @State private var api = API.shared
    @State private var player = Player.shared

    /// Spotify-Style Browse-Kategorien. Farben direkt aus Spotify iOS Listing.
    private let topCategories: [(name: String, color: Color, icon: String)] = [
        ("Musik", Color(red: 0.92, green: 0.29, blue: 0.51), "music.note"),                 // pink
        ("Podcasts", Color(red: 0.12, green: 0.60, blue: 0.60), "mic.fill"),                // teal
        ("Hoerbuecher", Color(red: 0.13, green: 0.22, blue: 0.55), "book.fill"),            // navy
        ("Live Events", Color(red: 0.49, green: 0.22, blue: 0.75), "mappin.and.ellipse"),   // purple
    ]

    private let genreCategories: [(name: String, color: Color)] = [
        ("Hip-Hop", Color(red: 0.86, green: 0.27, blue: 0.43)),
        ("Pop", Color(red: 0.95, green: 0.52, blue: 0.21)),
        ("Rock", Color(red: 0.60, green: 0.28, blue: 0.81)),
        ("Electronic", Color(red: 0.16, green: 0.60, blue: 0.87)),
        ("Chill", Color(red: 0.20, green: 0.60, blue: 0.48)),
        ("Workout", Color(red: 0.85, green: 0.35, blue: 0.25)),
        ("Focus", Color(red: 0.35, green: 0.42, blue: 0.75)),
        ("Party", Color(red: 0.91, green: 0.41, blue: 0.60)),
    ]

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()
            content
        }
        .navigationDestination(for: LibraryRoute.self) { route in
            switch route {
            case let .album(id): AlbumDetailView(albumId: id)
            case let .artist(id): ArtistDetailView(artistId: id)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Was willst du hoeren?")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .onChange(of: query) { _, newValue in
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                if Task.isCancelled { return }
                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    results = nil; error = nil; isLoading = false
                    return
                }
                await runSearch(newValue)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: DS.m) {
                    AvatarButton { showProfileSheet = true }
                    Text("Suche")
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
    }

    @ViewBuilder
    private var content: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            browseGrid
        } else if isLoading && results == nil {
            ProgressView().tint(DS.accent).frame(maxHeight: .infinity)
        } else if let error {
            ErrorView(message: error) {
                Task { await runSearch(query) }
            }
        } else if let results {
            resultsView(results)
        } else {
            Color.clear
        }
    }

    private var browseGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.xl) {
                // Hero-Tiles (4 grosse: Music/Podcasts/Audiobooks/Live Events)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.m), GridItem(.flexible(), spacing: DS.m)], spacing: DS.m) {
                    ForEach(topCategories, id: \.name) { cat in
                        heroTile(name: cat.name, color: cat.color, icon: cat.icon)
                    }
                }
                .padding(.horizontal, DS.l)
                .padding(.top, DS.l)

                // Genre-Section
                VStack(alignment: .leading, spacing: DS.m) {
                    Text("Durchsuche alle")
                        .font(DS.Font.title)
                        .foregroundStyle(DS.textPrimary)
                        .padding(.horizontal, DS.l)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.m), GridItem(.flexible(), spacing: DS.m)], spacing: DS.m) {
                        ForEach(genreCategories, id: \.name) { cat in
                            genreCard(name: cat.name, color: cat.color)
                        }
                    }
                    .padding(.horizontal, DS.l)
                }

                Spacer().frame(height: 140)
            }
        }
    }

    /// Grosser Hero-Tile (Music/Podcasts/etc) - Farbige Kachel mit Icon rechts unten rotiert.
    private func heroTile(name: String, color: Color, icon: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            query = name
        } label: {
            ZStack(alignment: .topLeading) {
                color

                // Icon rechts unten rotiert (Spotify-Style)
                Image(systemName: icon)
                    .font(.system(size: 56, weight: .black))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .rotationEffect(.degrees(25))
                    .offset(x: 40, y: 22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .clipped()

                Text(name)
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(.white)
                    .padding(DS.m)
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusM, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Standard-Genre-Card (kleinere farbige Kachel)
    private func genreCard(name: String, color: Color) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            query = name
        } label: {
            ZStack(alignment: .topLeading) {
                color
                Text(name)
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(.white)
                    .padding(DS.m)
            }
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusM, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func resultsView(_ r: SearchResponse) -> some View {
        if r.tracks.isEmpty && r.artists.isEmpty && r.albums.isEmpty {
            emptyResults
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    tracksSection(r.tracks)
                    artistsSection(r.artists)
                    albumsSection(r.albums)
                    Spacer().frame(height: 140)
                }
            }
        }
    }

    private var emptyResults: some View {
        VStack(spacing: DS.m) {
            Spacer().frame(height: 80)
            Image(systemName: "magnifyingglass").font(.system(size: 40)).foregroundStyle(DS.textSecondary)
            Text("Nichts gefunden").font(DS.Font.bodyLarge).foregroundStyle(DS.textPrimary)
            Text("Fuer \"\(query)\"").font(DS.Font.caption).foregroundStyle(DS.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func tracksSection(_ tracks: [TrackListItem]) -> some View {
        if !tracks.isEmpty {
            SectionHeader(title: "Songs")
            ForEach(tracks) { t in
                trackRowWithMenu(t, allTracks: tracks)
            }
        }
    }

    private func trackRowWithMenu(_ t: TrackListItem, allTracks: [TrackListItem]) -> some View {
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
    private func artistsSection(_ artists: [ArtistListItem]) -> some View {
        if !artists.isEmpty {
            SectionHeader(title: "Kuenstler")
            ForEach(artists) { a in artistRow(a) }
        }
    }

    @ViewBuilder
    private func albumsSection(_ albums: [AlbumListItem]) -> some View {
        if !albums.isEmpty {
            SectionHeader(title: "Alben")
            ForEach(albums) { alb in albumRow(alb) }
        }
    }

    private func artistRow(_ artist: ArtistListItem) -> some View {
        NavigationLink(value: LibraryRoute.artist(artist.id)) {
            HStack(spacing: DS.m) {
                CoverImage(url: artist.imageUrl, cornerRadius: 28, placeholder: "person.fill")
                    .frame(width: 56, height: 56)
                Text(artist.name)
                    .font(DS.Font.bodyLarge)
                    .foregroundStyle(DS.textPrimary)
                Spacer()
                Text("Kuenstler")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.textSecondary)
            }
            .padding(.horizontal, DS.xl)
            .padding(.vertical, DS.s)
        }
        .buttonStyle(.plain)
    }

    private func albumRow(_ album: AlbumListItem) -> some View {
        NavigationLink(value: LibraryRoute.album(album.id)) {
            HStack(spacing: DS.m) {
                CoverImage(url: album.coverUrl, cornerRadius: DS.radiusS)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title)
                        .font(DS.Font.bodyLarge)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text("Album · \(album.artist)")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, DS.xl)
            .padding(.vertical, DS.s)
        }
        .buttonStyle(.plain)
    }

    private func runSearch(_ q: String) async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let r = try await api.search(q: q)
            self.results = r
        } catch {
            self.error = error.localizedDescription
        }
    }
}
