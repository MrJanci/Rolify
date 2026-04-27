import SwiftUI

struct TrackRow: View {
    let track: TrackListItem
    let isCurrent: Bool
    let isPlaying: Bool
    let onTap: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isRevealed = false
    private let revealThreshold: CGFloat = 80

    var body: some View {
        ZStack(alignment: .leading) {
            // Background-Action (gruener Hintergrund mit Plus-Icon das auftaucht beim Swipen)
            if dragOffset > 0 {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "text.line.last.and.arrowtriangle.forward")
                            .font(.system(size: 18, weight: .bold))
                        if dragOffset >= revealThreshold {
                            Text("Zur Warteschlange")
                                .font(.system(size: 14, weight: .bold))
                                .transition(.opacity)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.leading, DS.xl + 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.accent.opacity(min(1.0, Double(dragOffset / revealThreshold))))
            }

            // Foreground-Row (mit horizontalem Drag)
            Button(action: {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                onTap()
            }) {
                HStack(spacing: DS.m) {
                    CoverImage(url: track.coverUrl, cornerRadius: DS.radiusS)
                        .frame(width: 56, height: 56)
                        .overlay(alignment: .center) {
                            if isCurrent {
                                ZStack {
                                    Color.black.opacity(0.45)
                                    Image(systemName: isPlaying ? "waveform" : "pause.fill")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(DS.accent)
                                        .symbolEffect(.variableColor.iterative, options: .repeat(.continuous), isActive: isPlaying)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: DS.radiusS, style: .continuous))
                            }
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(DS.Font.bodyLarge)
                            .foregroundStyle(isCurrent ? DS.accent : DS.textPrimary)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(formatDuration(ms: track.durationMs))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(DS.textSecondary)
                }
                .padding(.horizontal, DS.xl)
                .padding(.vertical, DS.s)
                .background(DS.bg)
            }
            .buttonStyle(.plain)
            .offset(x: dragOffset)
            .gesture(
                DragGesture(minimumDistance: 16)
                    .onChanged { v in
                        // Nur nach rechts swipen erlauben (positive translation)
                        let raw = v.translation.width
                        if raw > 0 {
                            dragOffset = min(140, raw)
                            // Haptic feedback einmalig wenn threshold erreicht
                            if !isRevealed && dragOffset >= revealThreshold {
                                isRevealed = true
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            } else if isRevealed && dragOffset < revealThreshold {
                                isRevealed = false
                            }
                        }
                    }
                    .onEnded { _ in
                        if dragOffset >= revealThreshold {
                            // Action triggern
                            PlaybackQueue.shared.appendAtEnd(QueueTrack(track))
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                        // Snap back
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = 0
                            isRevealed = false
                        }
                    }
            )
        }
        .clipShape(Rectangle())
    }
}
