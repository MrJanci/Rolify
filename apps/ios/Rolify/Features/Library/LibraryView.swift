import SwiftUI

/// Spotify-style "Your Library". Modular aufgebaut gegen Compile-Timeout.
struct LibraryView: View {
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
    @State private var profile: UserProfile?

    private let filterOptions = ["Playlists", "Alben", "Kuenstler", "Heruntergeladen"]

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
        .sheet(isPresented: $showCreateSheet) {
            CreateSheet(showCreatePlaylist: $showCreatePlaylist)
                .presentationDetents([.medium])
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
            if playlists.isEmpty { await load() }
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

    // MARK: Content Area

    @ViewBuilder
    private var contentArea: some View {
        if isLoading && playlists.isEmpty {
            ProgressView().tint(DS.accent).frame(maxHeight: .infinity)
        } else if let error {
            ErrorView(message: error) { Task { await load() } }
        } else {
            scrollContent
        }
    }

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                topHeader
                filterPills.padding(.top, DS.m)
                sortToggleRow.padding(.vertical, DS.m)
                playlistsList
                emptyStateIfNeeded
                Spacer().frame(height: 140)
            }
        }
        .refreshable { await load() }
    }

    // MARK: Header

    private var topHeader: some View {
        HStack(spacing: DS.m) {
            AvatarButton(avatarUrl: profile?.avatarUrl,
                         displayName: profile?.displayName ?? "U") {
                showProfile = true
            }
            Text("Deine Bibliothek")
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(DS.textPrimary)

            Spacer()
            searchButton
            plusButton
        }
        .padding(.horizontal, DS.l)
        .padding(.top, DS.s)
    }

    private var searchButton: some View {
        Button { } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(DS.textPrimary)
        }
        .buttonStyle(.plain)
    }

    private var plusButton: some View {
        Button {
            showCreateSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(DS.textPrimary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Filter + Sort

    private var filterPills: some View {
        TopBarPills(options: filterOptions,
                    selection: $selectedFilter,
                    allowDeselect: true)
    }

    private var sortToggleRow: some View {
        HStack {
            sortButton
            Spacer()
            gridToggleButton
        }
        .padding(.horizontal, DS.l)
    }

    private var sortButton: some View {
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
    }

    private var gridToggleButton: some View {
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

    // MARK: Playlists List

    private var displayedPlaylists: [PlaylistSummary] {
        if selectedFilter.isEmpty || selectedFilter == "Playlists" {
            return playlists
        }
        return []
    }

    private var playlistsList: some View {
        ForEach(displayedPlaylists) { p in
            playlistLink(p)
        }
    }

    private func playlistLink(_ p: PlaylistSummary) -> some View {
        NavigationLink(value: PlaylistRoute.detail(p.id, p.name)) {
            playlistRow(p)
        }
        .buttonStyle(.plain)
    }

    private func playlistRow(_ p: PlaylistSummary) -> some View {
        HStack(spacing: DS.m) {
            CoverImage(
                url: p.coverUrl.isEmpty ? nil : p.coverUrl,
                cornerRadius: DS.radiusS,
                placeholder: "music.note.list"
            )
            .frame(width: 56, height: 56)

            playlistMetadata(p)
            Spacer()
        }
        .padding(.horizontal, DS.l)
        .padding(.vertical, DS.s)
    }

    private func playlistMetadata(_ p: PlaylistSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(p.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            playlistSubtitle(p)
        }
    }

    private func playlistSubtitle(_ p: PlaylistSummary) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "pin.fill")
                .font(.system(size: 10))
                .foregroundStyle(DS.accent)
            Text("Playlist")
                .font(.system(size: 13))
                .foregroundStyle(DS.textSecondary)
            playlistTrackCount(p)
        }
    }

    @ViewBuilder
    private func playlistTrackCount(_ p: PlaylistSummary) -> some View {
        if p.trackCount > 0 {
            Text("·").foregroundStyle(DS.textSecondary)
            Text("\(p.trackCount) Tracks")
                .font(.system(size: 13))
                .foregroundStyle(DS.textSecondary)
        }
    }

    @ViewBuilder
    private var emptyStateIfNeeded: some View {
        if displayedPlaylists.isEmpty {
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
    }

    // MARK: Data

    private func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            self.playlists = try await api.myPlaylists()
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
