import SwiftUI

enum Tab: Hashable {
    case home, search, library, profile
}

struct AppRoot: View {
    @State private var api = API.shared
    @State private var player = Player.shared
    @State private var selectedTab: Tab = .library
    @State private var showNowPlaying = false

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

                NavigationStack { ProfileView() }
                    .tabItem { Label("Profil", systemImage: "person.circle.fill") }
                    .tag(Tab.profile)
            }
            .tint(DS.accent)

            if player.currentTrack != nil {
                MiniPlayer {
                    showNowPlaying = true
                }
                .padding(.bottom, 49)   // sits directly above TabBar
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: player.currentTrack?.trackId)
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingSheet()
                .presentationDragIndicator(.visible)
        }
    }
}
