import SwiftUI

struct MiniPlayer: View {
    @State private var player = Player.shared
    @State private var dragOffset: CGFloat = 0
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
                .offset(x: dragOffset)
                .opacity(1.0 - Double(min(abs(dragOffset), 200)) / 250.0)
            }
            .buttonStyle(.plain)
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        // Nur horizontale swipes (ignore vertical)
                        let h = value.translation.width
                        let v = value.translation.height
                        if abs(h) > abs(v) {
                            dragOffset = h
                        }
                    }
                    .onEnded { value in
                        if abs(value.translation.width) > 120 {
                            // Swipe weit genug → Player stoppen (Spotify-Style dismiss)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.easeOut(duration: 0.2)) {
                                dragOffset = value.translation.width > 0 ? 400 : -400
                            }
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(200))
                                player.stop()
                                dragOffset = 0
                            }
                        } else {
                            withAnimation(.spring(response: 0.3)) { dragOffset = 0 }
                        }
                    }
            )
        }
    }
}
