import SwiftUI

/// Home-Tab — Spotify-Style "For You" Feed. In Chunk 12 wird das zu Shelves ausgebaut.
/// Fuer jetzt: nur die Recent-Tracks (gleiche Daten wie Library, anders praesentiert).
struct HomeView: View {
    @State private var tracks: [TrackListItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var api = API.shared
    @State private var player = Player.shared

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            if isLoading {
                ProgressView().tint(DS.accent).frame(maxHeight: .infinity)
            } else if let error {
                ErrorView(message: error) { Task { await load() } }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        headline
                        SectionHeader(title: "Neu hinzugefuegt")
                        LazyVStack(spacing: 0) {
                            ForEach(tracks.prefix(10)) { t in
                                TrackRow(
                                    track: t,
                                    isCurrent: player.currentTrack?.trackId == t.id,
                                    isPlaying: player.isPlaying && player.currentTrack?.trackId == t.id
                                ) {
                                    Task { await player.play(trackId: t.id) }
                                }
                            }
                        }
                        Spacer().frame(height: 120)
                    }
                }
                .refreshable { await load() }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Text("Home")
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.textPrimary)
            }
        }
        .task { if tracks.isEmpty { await load() } }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            Text("Guten Abend")
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(DS.textPrimary)
        }
        .padding(.horizontal, DS.xl)
        .padding(.top, DS.s)
        .padding(.bottom, DS.s)
    }

    private func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let home = try await api.browseHome()
            self.tracks = home.tracks
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: DS.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32)).foregroundStyle(.red)
            Text(message)
                .foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Nochmal", action: onRetry)
                .foregroundStyle(DS.accent)
        }
        .frame(maxHeight: .infinity)
    }
}
