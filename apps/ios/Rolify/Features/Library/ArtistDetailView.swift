import SwiftUI

struct ArtistDetailView: View {
    let artistId: String

    @State private var detail: ArtistDetail?
    @State private var isLoading = true
    @State private var error: String?
    @State private var api = API.shared
    @State private var player = Player.shared

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            if let detail {
                ScrollView {
                    VStack(spacing: 0) {
                        GradientHeader(
                            title: detail.name,
                            subtitle: "Kuenstler",
                            coverUrl: detail.imageUrl.isEmpty ? nil : detail.imageUrl,
                            baseColor: Color(red: 0.60, green: 0.28, blue: 0.81)
                        ) {
                            Button {
                                guard let first = detail.topTracks.first else { return }
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                Task { await player.play(trackId: first.id) }
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

                        if !detail.topTracks.isEmpty {
                            SectionHeader(title: "Top-Tracks")
                            LazyVStack(spacing: 0) {
                                ForEach(detail.topTracks) { t in
                                    Button {
                                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                        Task { await player.play(trackId: t.id) }
                                    } label: {
                                        HStack(spacing: DS.m) {
                                            CoverImage(url: t.coverUrl, cornerRadius: DS.radiusS)
                                                .frame(width: 44, height: 44)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(t.title)
                                                    .font(DS.Font.body)
                                                    .foregroundStyle(player.currentTrack?.trackId == t.id ? DS.accent : DS.textPrimary)
                                                    .lineLimit(1)
                                                Text(t.album)
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
                                }
                            }
                        }

                        if !detail.albums.isEmpty {
                            SectionHeader(title: "Alben")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: DS.m) {
                                    ForEach(detail.albums) { a in
                                        NavigationLink(value: LibraryRoute.album(a.id)) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                CoverImage(url: a.coverUrl, cornerRadius: DS.radiusS)
                                                    .frame(width: 140, height: 140)
                                                Text(a.title)
                                                    .font(DS.Font.body)
                                                    .foregroundStyle(DS.textPrimary)
                                                    .lineLimit(1)
                                                    .frame(width: 140, alignment: .leading)
                                                Text(String(a.releaseYear))
                                                    .font(DS.Font.footnote)
                                                    .foregroundStyle(DS.textSecondary)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, DS.xl)
                            }
                        }

                        Spacer().frame(height: 120)
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
            self.detail = try await api.artistDetail(id: artistId)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
