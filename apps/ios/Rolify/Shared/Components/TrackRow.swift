import SwiftUI

struct TrackRow: View {
    let track: TrackListItem
    let isCurrent: Bool
    let isPlaying: Bool
    let onTap: () -> Void

    var body: some View {
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
        }
        .buttonStyle(.plain)
    }
}
