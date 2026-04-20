import SwiftUI

struct NowPlayingSheet: View {
    @State private var player = Player.shared
    @State private var queue = PlaybackQueue.shared
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var showQueue = false

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

                    Spacer().frame(height: DS.xl)

                    controlRow

                    Spacer()

                    bottomActions
                        .padding(.bottom, DS.xl)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showQueue) {
            QueueView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var progressBar: some View {
        VStack(spacing: DS.xs) {
            GeometryReader { geo in
                let actualProgress = player.durationSeconds > 0 ? player.progressSeconds / player.durationSeconds : 0
                let progress = isDragging ? dragProgress : actualProgress
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(DS.textPrimary)
                        .frame(width: max(0, geo.size.width * progress))
                }
                .frame(height: 4)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let newProgress = min(max(0, value.location.x / geo.size.width), 1)
                            dragProgress = newProgress
                        }
                        .onEnded { value in
                            let newProgress = min(max(0, value.location.x / geo.size.width), 1)
                            let seconds = newProgress * player.durationSeconds
                            player.seek(seconds: seconds)
                            isDragging = false
                        }
                )
            }
            .frame(height: 12)
            .padding(.horizontal, DS.xxl)

            HStack {
                Text(formatDuration(seconds: isDragging ? dragProgress * player.durationSeconds : player.progressSeconds))
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
        HStack(spacing: 28) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                queue.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(queue.shuffle ? DS.accent : DS.textSecondary)
            }
            .buttonStyle(.plain)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task { if let prev = queue.rewind() { await player.play(trackId: prev.id) } }
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(DS.textPrimary)
            }
            .buttonStyle(.plain)
            .disabled(queue.order.isEmpty)

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
                Task { if let next = queue.advance() { await player.play(trackId: next.id) } }
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(DS.textPrimary)
            }
            .buttonStyle(.plain)
            .disabled(queue.order.isEmpty)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                queue.cycleRepeat()
            } label: {
                Image(systemName: repeatIcon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(queue.repeatMode == .off ? DS.textSecondary : DS.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private var repeatIcon: String {
        switch queue.repeatMode {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private var bottomActions: some View {
        HStack {
            Spacer()
            Button {
                showQueue = true
            } label: {
                HStack(spacing: DS.s) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Warteschlange")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(DS.textSecondary)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }
}
