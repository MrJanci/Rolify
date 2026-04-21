import SwiftUI

struct AlbumDetailView: View {
    let albumId: String

    @State private var detail: AlbumDetail?
    @State private var isLoading = true
    @State private var error: String?
    @State private var isSaved = false
    @State private var api = API.shared
    @State private var player = Player.shared

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            if let detail {
                ScrollView {
                    VStack(spacing: 0) {
                        GradientHeader(
                            title: detail.title,
                            subtitle: "\(detail.artist.name) · \(String(detail.releaseYear))",
                            coverUrl: detail.coverUrl,
                            baseColor: Color(red: 0.22, green: 0.35, blue: 0.58)
                        ) {
                            HStack(spacing: DS.m) {
                                Button { Task { await toggleSave() } } label: {
                                    Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle")
                                        .font(.system(size: 28, weight: .semibold))
                                        .foregroundStyle(isSaved ? DS.accent : DS.textSecondary)
                                        .contentTransition(.symbolEffect(.replace))
                                }
                                .buttonStyle(.plain)

                                Button {
                                    guard let first = detail.tracks.first else { return }
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    let q = detail.tracks.map { QueueTrack($0) }
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
                            }
                        }

                        Divider().background(DS.divider)

                        LazyVStack(spacing: 0) {
                            ForEach(detail.tracks) { t in
                                Button {
                                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                    let q = detail.tracks.map { QueueTrack($0) }
                                    Task { await player.play(queue: q, startingAt: t.id) }
                                } label: {
                                    HStack(spacing: DS.m) {
                                        Text("\(t.trackNumber)")
                                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                                            .foregroundStyle(DS.textTertiary)
                                            .frame(width: 26, alignment: .trailing)
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
                                    .padding(.vertical, DS.s)
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer().frame(height: 120)
                        }
                    }
                }
            } else if isLoading {
                ProgressView().tint(DS.accent).frame(maxHeight: .infinity)
            } else if let error {
                ErrorView(message: error) { Task { await load() } }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            self.detail = try await api.albumDetail(id: albumId)
            self.isSaved = (try? await api.isAlbumSaved(albumId)) ?? false
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func toggleSave() async {
        let wasSaved = isSaved
        isSaved.toggle()  // optimistic
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        do {
            if wasSaved { try await api.unsaveAlbum(albumId) }
            else { try await api.saveAlbum(albumId) }
        } catch {
            await MainActor.run { isSaved = wasSaved }
        }
    }
}
