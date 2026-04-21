import SwiftUI

enum Tab: Hashable {
    case home, search, library
}

/// Spotify-style App-Root: TabView mit Home / Search / Your Library + Create (Modal).
struct AppRoot: View {
    @State private var api = API.shared
    @State private var player = Player.shared
    @State private var selectedTab: Tab = .home
    @State private var showNowPlaying = false
    @State private var showCreateSheet = false
    @State private var showCreatePlaylist = false

    var body: some View {
        if api.isLoggedIn {
            authenticatedRoot
        } else {
            LoginView()
        }
    }

    @ViewBuilder
    private var authenticatedRoot: some View {
        ZStack(alignment: .bottom) {
            mainTabView
            miniPlayerOverlay
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85),
                   value: player.currentTrack?.trackId)
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingSheet().presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateSheet(showCreatePlaylist: $showCreatePlaylist)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCreatePlaylist) {
            CreatePlaylistSheet { _ in }
                .presentationDetents([.medium])
        }
    }

    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)

            NavigationStack { SearchView() }
                .tabItem { Label("Suche", systemImage: "magnifyingglass") }
                .tag(Tab.search)

            NavigationStack { LibraryView() }
                .tabItem { Label("Bibliothek", systemImage: "books.vertical.fill") }
                .tag(Tab.library)
        }
        .tint(DS.accent)
    }

    @ViewBuilder
    private var miniPlayerOverlay: some View {
        if player.currentTrack != nil {
            MiniPlayer { showNowPlaying = true }
                .padding(.bottom, 55)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
