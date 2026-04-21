import SwiftUI

enum Tab: Hashable {
    case home, search, library
}

/// Spotify-style App-Root: TabView mit Home / Search / Your Library + Create (Modal).
/// MiniPlayer sitzt zwischen Content und TabBar.
struct AppRoot: View {
    @State private var api = API.shared
    @State private var player = Player.shared
    @State private var selectedTab: Tab = .home
    @State private var showNowPlaying = false
    @State private var showCreateSheet = false
    @State private var showCreatePlaylist = false

    var body: some View {
        Group {
            if api.isLoggedIn {
                authenticatedRoot
            } else {
                LoginView()
            }
        }
    }

    @ViewBuilder
    private var authenticatedRoot: some View {
        ZStack(alignment: .bottom) {
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
            .toolbarBackground(DS.bg.opacity(0.95), for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)

            // Create-Button als floating "+" quasi-Tab
            HStack {
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showCreateSheet = true
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .bold))
                        Text("Erstellen")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 80)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 2)
            }
            .frame(height: 49)

            if player.currentTrack != nil {
                MiniPlayer { showNowPlaying = true }
                    .padding(.bottom, 55)   // oberhalb der TabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: player.currentTrack?.trackId)
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingSheet()
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateSheet(showCreatePlaylist: $showCreatePlaylist)
                .presentationDetents([.height(540)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCreatePlaylist) {
            CreatePlaylistSheet { _ in
                // user should refresh Library to see new playlist
            }
            .presentationDetents([.medium])
        }
    }
}
