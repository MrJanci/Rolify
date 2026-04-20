import SwiftUI

struct NowPlayingSheet: View {
    @State private var player = Player.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [DS.bgElevated, DS.bg],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            if let track = player.currentTrack {
                VStack(spacing: 0) {
                    Spacer().frame(height: DS.xl)

                    CoverImage(url: track.coverUrl, cornerRadius: DS.radiusL)
                        .frame(width: 320, height: 320)
                        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)

                    Spacer().frame(height: 40)

                    VStack(spacing: DS.xs) {
                        Text(track.title)
                            .font(.system(size: 24, weight: .black))
                            .foregroundStyle(DS.textPrimary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        Text(track.artist)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(DS.textSecondary)
                    }
                    .padding(.horizontal, DS.xxl)

                    Spacer().frame(height: DS.xxxl)

                    progressBar

                    Spacer().frame(height: DS.xxl)

                    controlRow

                    Spacer()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var progressBar: some View {
        VStack(spacing: DS.xs) {
            GeometryReader { geo in
                let progress = player.durationSeconds > 0 ? player.progressSeconds / player.durationSeconds : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(DS.textPrimary)
                        .frame(width: max(0, geo.size.width * progress))
                }
                .frame(height: 4)
            }
            .frame(height: 4)
            .padding(.horizontal, DS.xxl)

            HStack {
                Text(formatDuration(seconds: player.progressSeconds))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DS.textSecondary)
                Spacer()
                Text("-" + formatDuration(seconds: max(0, player.durationSeconds - player.progressSeconds)))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DS.textSecondary)
            }
            .padding(.horizontal, DS.xxl)
        }
    }

    private var controlRow: some View {
        HStack(spacing: 40) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                // Chunk 11: queue rewind
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(DS.textSecondary)
            }
            .disabled(true)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle().fill(DS.textPrimary)
                        .frame(width: 72, height: 72)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(.black)
                }
            }
            .buttonStyle(.plain)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                // Chunk 11: queue advance
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(DS.textSecondary)
            }
            .disabled(true)
        }
    }
}
