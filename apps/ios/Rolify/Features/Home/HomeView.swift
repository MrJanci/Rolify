import SwiftUI

struct HomeView: View {
    @State private var shelves: [HomeShelf] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var api = API.shared
    @State private var player = Player.shared

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            if isLoading && shelves.isEmpty {
                ProgressView().tint(DS.accent).frame(maxHeight: .infinity)
            } else if let error {
                ErrorView(message: error) { Task { await load() } }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DS.l) {
                        greetingHeader
                        ForEach(shelves) { shelf in
                            HomeShelfView(shelf: shelf, player: player)
                        }
                        Spacer().frame(height: 120)
                    }
                }
                .refreshable { await load() }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: PlaylistRoute.self) { route in
            switch route {
            case let .detail(id, name):
                PlaylistDetailView(playlistId: id, initialName: name)
            }
        }
        .navigationDestination(for: LibraryRoute.self) { route in
            switch route {
            case let .album(id): AlbumDetailView(albumId: id)
            case let .artist(id): ArtistDetailView(artistId: id)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Text("Home")
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.textPrimary)
            }
        }
        .task { if shelves.isEmpty { await load() } }
    }

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: DS.xs) {
            Text(timeBasedGreeting())
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(DS.textPrimary)
        }
        .padding(.horizontal, DS.xl)
        .padding(.top, DS.s)
    }

    private func timeBasedGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Guten Morgen"
        case 12..<18: return "Guten Tag"
        default: return "Guten Abend"
        }
    }

    private func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let home = try await api.browseHome()
            self.shelves = home.shelves ?? []
        } catch {
            self.error = error.localizedDescription
        }
    }
}
