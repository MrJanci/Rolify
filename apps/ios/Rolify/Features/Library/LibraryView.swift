import SwiftUI

struct LibraryView: View {
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
            } else if tracks.isEmpty {
                VStack(spacing: DS.m) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 44, weight: .regular))
                        .foregroundStyle(DS.textSecondary)
                    Text("Keine Tracks")
                        .font(DS.Font.body)
                        .foregroundStyle(DS.textSecondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(tracks) { t in
                            TrackRow(
                                track: t,
                                isCurrent: player.currentTrack?.trackId == t.id,
                                isPlaying: player.isPlaying && player.currentTrack?.trackId == t.id
                            ) {
                                Task { await player.play(trackId: t.id) }
                            }
                            Divider().background(DS.divider).padding(.leading, 88)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bibliothek")
                        .font(DS.Font.headline)
                        .foregroundStyle(DS.textPrimary)
                    Text("\(tracks.count) Tracks")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.textSecondary)
                }
            }
        }
        .task { if tracks.isEmpty { await load() } }
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
