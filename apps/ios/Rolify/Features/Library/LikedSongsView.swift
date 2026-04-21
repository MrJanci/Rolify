import SwiftUI

/// "Liked Songs" Pseudo-Playlist - zeigt alle gelikten Tracks.
struct LikedSongsView: View {
    @State private var tracks: [API.LikedTracksResponse.Item] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showAddToPlaylist = false
    @State private var pendingTrackId = ""
    @State private var pendingTrackTitle = ""
    @State private var api = API.shared
    @State private var player = Player.shared

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()
            content
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(trackId: pendingTrackId, trackTitle: pendingTrackTitle)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && tracks.isEmpty {
            ProgressView().tint(DS.accent).frame(maxHeight: .infinity)
        } else if let error {
            ErrorView(message: error) { Task { await load() } }
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    LazyVStack(spacing: 0) {
                        ForEach(tracks) { t in trackRow(t) }
                        Spacer().frame(height: 140)
                    }
                }
            }
            .refreshable { await load() }
        }
    }

    private var hero: some View {
        VStack(spacing: DS.m) {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.55, green: 0.20, blue: 0.95), DS.accentDeep],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Image(systemName: "heart.fill")
                    .font(.system(size: 80, weight: .black))
                    .foregroundStyle(.white)
            }
            .frame(width: 220, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusM))
            .shadow(color: .black.opacity(0.4), radius: 18, y: 10)

            Text("Gelikte Songs")
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(DS.textPrimary)

            Text("\(tracks.count) Tracks")
                .font(DS.Font.caption)
                .foregroundStyle(DS.textSecondary)

            Button {
                guard let first = tracks.first else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                let q = tracks.map { QueueTrack(id: $0.id, title: $0.title, artist: $0.artist, coverUrl: $0.coverUrl, durationMs: $0.durationMs) }
                Task { await player.play(queue: q, startingAt: first.id) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill").font(.system(size: 16, weight: .black))
                    Text("Abspielen").font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 32)
                .frame(height: 48)
                .background(DS.accent)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, DS.s)
            .disabled(tracks.isEmpty)
        }
        .padding(.horizontal, DS.xl)
        .padding(.vertical, DS.xxl)
    }

    private func trackRow(_ t: API.LikedTracksResponse.Item) -> some View {
        let queueTrack = QueueTrack(id: t.id, title: t.title, artist: t.artist, coverUrl: t.coverUrl, durationMs: t.durationMs)
        return Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            let q = tracks.map { QueueTrack(id: $0.id, title: $0.title, artist: $0.artist, coverUrl: $0.coverUrl, durationMs: $0.durationMs) }
            Task { await player.play(queue: q, startingAt: t.id) }
        } label: {
            HStack(spacing: DS.m) {
                CoverImage(url: t.coverUrl, cornerRadius: DS.radiusS)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.title)
                        .font(DS.Font.body)
                        .foregroundStyle(player.currentTrack?.trackId == t.id ? DS.accent : DS.textPrimary)
                        .lineLimit(1)
                    Text(t.artist)
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(formatDuration(ms: t.durationMs))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(DS.textSecondary)
            }
            .padding(.horizontal, DS.xl)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .rolifyTrackContextMenu(
            queueTrack: queueTrack,
            albumId: t.albumId,
            showAddToPlaylist: $showAddToPlaylist,
            pendingTrackId: $pendingTrackId,
            pendingTrackTitle: $pendingTrackTitle
        )
    }

    private func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do { self.tracks = try await api.likedTracks() }
        catch { self.error = error.localizedDescription }
    }
}
