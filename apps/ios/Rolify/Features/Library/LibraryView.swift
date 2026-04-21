import SwiftUI

struct LibraryView: View {
    @State private var playlists: [PlaylistSummary] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showCreatePlaylist = false
    @State private var api = API.shared

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
                Text("Deine Bibliothek").font(.system(size: 22, weight: .black)).foregroundStyle(DS.textPrimary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreatePlaylist = true } label: {
                    Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(DS.textPrimary)
                }
            }
        }
        .sheet(isPresented: $showCreatePlaylist) {
            CreatePlaylistSheet { created in playlists.insert(created, at: 0) }
                .presentationDetents([.medium])
        }
        .task { if playlists.isEmpty { await load() } }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && playlists.isEmpty {
            ProgressView().tint(DS.accent).frame(maxHeight: .infinity)
        } else if let error {
            ErrorView(message: error) { Task { await load() } }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(playlists) { p in
                        NavigationLink(value: PlaylistRoute.detail(p.id, p.name)) {
                            HStack(spacing: DS.m) {
                                CoverImage(url: p.coverUrl.isEmpty ? nil : p.coverUrl, cornerRadius: DS.radiusS, placeholder: "music.note.list")
                                    .frame(width: 56, height: 56)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.textPrimary).lineLimit(1)
                                    Text("Playlist · \(p.trackCount) Tracks").font(.system(size: 13)).foregroundStyle(DS.textSecondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, DS.l).padding(.vertical, DS.s)
                        }
                        .buttonStyle(.plain)
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
        do { self.playlists = try await api.myPlaylists() } catch { self.error = error.localizedDescription }
    }
}

enum PlaylistRoute: Hashable { case detail(String, String?) }
enum LibraryRoute: Hashable {
    case album(String)
    case artist(String)
}
