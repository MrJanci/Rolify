import SwiftUI

enum LibraryFilter: String, CaseIterable, Identifiable {
    case playlists = "Playlists"
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
    @State private var isLoading = true
    @State private var error: String?
    @State private var showCreateSheet = false
    @State private var showProfileSheet = false
    @State private var filter: LibraryFilter = .playlists
    @State private var sort: LibrarySort = .recent
    @State private var searchText = ""
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
                HStack(spacing: DS.m) {
                    AvatarButton { showProfileSheet = true }
                    Text("Deine Bibliothek")
                        .font(DS.Font.title)
                        .foregroundStyle(DS.textPrimary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(DS.textPrimary)
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateSheet { created in playlists.insert(created, at: 0) }
                .presentationDetents([.height(420)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showProfileSheet) {
            ProfileSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
            Image(systemName: "list.bullet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.textSecondary)
        }
        .padding(.horizontal, DS.l)
        .padding(.vertical, DS.s)
    }

    // MARK: - List

    @ViewBuilder
    private var listView: some View {
        switch filter {
        case .playlists: playlistList
        case .albums: emptyPlaceholder(title: "Alben folgen bald", message: "Saved-Alben-API kommt in v0.14")
        case .artists: emptyPlaceholder(title: "Kuenstler folgen bald", message: "Saved-Artists-API kommt in v0.14")
        }
    }

    private var playlistList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
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
                HStack(spacing: 4) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DS.accent)
                    Text("Playlist · \(p.trackCount) Tracks")
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
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sort-Logic

    private var sortedPlaylists: [PlaylistSummary] {
        switch sort {
        case .recent: return playlists
        case .name: return playlists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .creator: return playlists   // creator-Info fehlt im Summary — fallback auf name
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
