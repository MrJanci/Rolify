import SwiftUI

struct MiniPlayer: View {
    @State private var player = Player.shared
    let onTap: () -> Void

    var body: some View {
        if let track = player.currentTrack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onTap()
            } label: {
                HStack(spacing: DS.m) {
                    CoverImage(url: track.coverUrl, cornerRadius: DS.radiusS)
                        .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title).font(.system(size: 14, weight: .bold))
                            .foregroundStyle(DS.textPrimary).lineLimit(1)
                        Text(track.artist).font(.system(size: 12))
                            .foregroundStyle(DS.textSecondary).lineLimit(1)
                    }
                    Spacer(minLength: DS.s)

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(DS.textPrimary)
                            .frame(width: 38, height: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        player.stop()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(DS.textSecondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous)
                        .fill(DS.bgElevated)
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                )
                .overlay(alignment: .bottom) {
                    GeometryReader { geo in
                        let progress = player.durationSeconds > 0 ? player.progressSeconds / player.durationSeconds : 0
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.1))
                            RoundedRectangle(cornerRadius: 1).fill(DS.accent)
                                .frame(width: max(0, geo.size.width * progress))
                        }
                        .frame(height: 2)
                        .padding(.horizontal, 10)
                    }
                    .frame(height: 2)
                    .padding(.bottom, 2)
                }
                .padding(.horizontal, DS.m)
            }
            .buttonStyle(.plain)
        }
    }
}
