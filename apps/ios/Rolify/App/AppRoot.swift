import SwiftUI

enum Tab: Hashable {
    case home, search, library, create
}

/// Global state fuer Create-Sheet-Steuerung — damit Plus-Tab + Plus-Button
/// (falls irgendwo noch) beide dasselbe Sheet oeffnen.
@Observable
@MainActor
final class CreateRouter {
    static let shared = CreateRouter()
    var showCreateSheet = false
}

struct AppRoot: View {
    @State private var api = API.shared
    @State private var player = Player.shared
    @State private var jam = JamOrchestrator.shared
    @State private var router = CreateRouter.shared
    @State private var selectedTab: Tab = .library
    @State private var previousTab: Tab = .library
    @State private var showNowPlaying = false
    @State private var showJam = false

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

                // "Create" Tab: Tapping opens CreateSheet statt Tab-Switch.
                // Wir nutzen .onChange um sofort zurueckzuspringen + Sheet zu triggern.
                Color.clear
                    .tabItem { Label("Create", systemImage: "plus.circle.fill") }
                    .tag(Tab.create)
            }
            .tint(DS.accent)
            .onChange(of: selectedTab) { old, new in
                if new == .create {
                    // Direkt zurueckspringen + Sheet auf
                    selectedTab = old == .create ? .library : old
                    router.showCreateSheet = true
                } else {
                    previousTab = new
                }
            }

            VStack(spacing: 6) {
                if jam.isConnected, let code = jam.activeCode {
                    jamBanner(code: code)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if player.currentTrack != nil {
                    MiniPlayer { showNowPlaying = true }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, 49)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: player.currentTrack?.trackId)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: jam.isConnected)
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingSheet()
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showJam) {
            JamSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $router.showCreateSheet) {
            CreateSheet(
                onPlaylistCreated: { _ in },
                onMixedCreated: { _ in }
            )
            .presentationDetents([.height(460)])
            .presentationDragIndicator(.visible)
        }
    }

    private func jamBanner(code: String) -> some View {
        Button { showJam = true } label: {
            HStack(spacing: DS.s) {
                Image(systemName: "wifi")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DS.accent)
                Text("Jam aktiv · \(code)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.textPrimary)
                Text("\(jam.client.participants.count) dabei")
                    .font(DS.Font.footnote)
                    .foregroundStyle(DS.textSecondary)
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DS.textSecondary)
            }
            .padding(.horizontal, DS.m)
            .frame(height: 40)
            .background(DS.bgElevated)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(DS.accent.opacity(0.3), lineWidth: 1))
            .padding(.horizontal, DS.m)
        }
        .buttonStyle(.plain)
    }
}
