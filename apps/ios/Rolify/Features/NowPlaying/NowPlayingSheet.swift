import SwiftUI

struct NowPlayingSheet: View {
    @State private var player = Player.shared
    @State private var queue = PlaybackQueue.shared
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var showQueue = false
    @State private var isLiked = false  // TODO: wire auf /me/likes wenn Backend steht

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

                    Spacer().frame(height: 32)

                    titleRow(track: track)

                    Spacer().frame(height: 24)

                    progressBar

                    Spacer().frame(height: DS.l)

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

    // MARK: - Title + Heart + Dots

    private func titleRow(track: StreamManifest) -> some View {
        HStack(alignment: .center, spacing: DS.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(2)
                Text(track.artist)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.s)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isLiked.toggle()
            } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isLiked ? DS.accent : DS.textSecondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.xxl)
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

    // MARK: - Bottom actions (AirPlay + Share + Queue)

    private var bottomActions: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "hifispeaker.and.appletv")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if let t = player.currentTrack {
                    UIPasteboard.general.string = "rolify://track/\(t.trackId)"
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer().frame(width: DS.xxl)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.xxl)
    }
}
