import SwiftUI

struct QueueView: View {
    @State private var queue = PlaybackQueue.shared
    @State private var player = Player.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("Warteschlange")
                        .font(DS.Font.headline)
                        .foregroundStyle(DS.textPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(DS.textSecondary)
                    }
                }
                .padding(.horizontal, DS.xl)
                .padding(.top, DS.xl)
                .padding(.bottom, DS.m)

                if let current = queue.currentTrack {
                    SectionHeader(title: "Jetzt laeuft")
                    queueTrackRow(current, isCurrent: true)
                }

                if !queue.upNext.isEmpty {
                    SectionHeader(title: "Als naechstes")
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(queue.upNext.enumerated()), id: \.element.id) { idx, t in
                                queueTrackRow(t, isCurrent: false)
                            }
                        }
                    }
                } else if queue.currentTrack != nil {
                    Text("Nichts mehr in der Warteschlange")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, DS.xl)
                    Spacer()
                } else {
                    Spacer()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func queueTrackRow(_ t: QueueTrack, isCurrent: Bool) -> some View {
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
                        .foregroundStyle(isCurrent ? DS.accent : DS.textPrimary)
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
    }
}
