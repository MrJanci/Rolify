import SwiftUI

/// Minimale LibraryView - Fallback-Version.
struct LibraryView: View {
    @State private var playlists: [PlaylistSummary] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showCreateSheet = false
    @State private var showCreatePlaylist = false
    @State private var showProfile = false
    @State private var api = API.shared
    @State private var profile: UserProfile?

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
            ToolbarItem(placement: .principal) {
                Text("Deine Bibliothek")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(DS.textPrimary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreateSheet = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(DS.textPrimary)
                }
            }
        }
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
        .task {
            await loadProfile()
            if playlists.isEmpty { await load() }
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
        if isLoading && playlists.isEmpty {
            ProgressView().tint(DS.accent).frame(maxHeight: .infinity)
        } else if let error {
            ErrorView(message: error) { Task { await load() } }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(playlists) { p in
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

    private func playlistRow(_ p: PlaylistSummary) -> some View {
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
                Text("Playlist · \(p.trackCount) Tracks")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, DS.l)
        .padding(.vertical, DS.s)
    }

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
