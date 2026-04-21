import SwiftUI

/// Full-screen Now-Playing Sheet (Spotify-style).
///
/// Layout (top->bottom):
///   [v chevron]   [Playlist/Context name]   [...]
///   [big Cover-Image, ~full-width]
///   Track-Title (bold xl) + Artist (smaller)   [heart-save]
///   [Progress slider] 0:00 ----- -3:24
///   [shuffle] [prev] [PLAY] [next] [repeat]
///   [speaker-device] ............. [share] [queue]
///   [Lyrics Peek-Card]
struct NowPlayingSheet: View {
    @State private var player = Player.shared
    @State private var queue = PlaybackQueue.shared
    @Environment(\.dismiss) var dismiss
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var showQueue = false
    @State private var contextName: String = ""

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                headerRow
                    .padding(.horizontal, DS.l)
                    .padding(.top, DS.m)

                Spacer().frame(height: DS.xl)

                if let track = player.currentTrack {
                    coverImage(track)
                }

                Spacer().frame(height: 28)

                titleRow

                Spacer().frame(height: DS.xl)

                progressBar

                Spacer().frame(height: 16)

                controlRow

                Spacer().frame(height: DS.xxl)

                bottomActions
                    .padding(.horizontal, DS.xl)

                lyricsCard
                    .padding(.top, DS.m)
                    .padding(.horizontal, DS.m)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showQueue) {
            QueueView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Header (v / title / ...)

    private var headerRow: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.textPrimary)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(contextName.isEmpty ? "Wird gespielt" : contextName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.textPrimary)

            Spacer()

            Button { } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.textPrimary)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Cover

    private func coverImage(_ track: StreamManifest) -> some View {
        CoverImage(url: track.coverUrl, cornerRadius: DS.radiusM)
            .frame(width: 340, height: 340)
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
    }

    // MARK: Title-Row mit Save-Check

    private var titleRow: some View {
        HStack(alignment: .top, spacing: DS.m) {
            if let track = player.currentTrack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: DS.xs) {
                        Text("E")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(DS.textSecondary)
                            .frame(width: 16, height: 16)
                            .background(Color.white.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        Text(track.title)
                            .font(.system(size: 24, weight: .black))
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(2)
                    }
                    Text(track.artist)
                        .font(.system(size: 15))
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Green Save Check (placeholder — future: toggle Library)
                ZStack {
                    Circle().fill(DS.accent).frame(width: 32, height: 32)
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                }
            }
        }
        .padding(.horizontal, DS.xl)
    }

    // MARK: Progress

    private var progressBar: some View {
        VStack(spacing: DS.xs) {
            GeometryReader { geo in
                let actualProgress = player.durationSeconds > 0 ? player.progressSeconds / player.durationSeconds : 0
                let progress = isDragging ? dragProgress : actualProgress
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.20))
                    Capsule().fill(DS.textPrimary)
                        .frame(width: max(0, geo.size.width * progress))
                }
                .frame(height: 4)
                .contentShape(Rectangle())
                .gesture(dragGesture(width: geo.size.width))
            }
            .frame(height: 16)
            .padding(.horizontal, DS.xl)

            HStack {
                Text(formatDuration(seconds: isDragging ? dragProgress * player.durationSeconds : player.progressSeconds))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DS.textSecondary)
                Spacer()
                Text("-" + formatDuration(seconds: max(0, player.durationSeconds - player.progressSeconds)))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DS.textSecondary)
            }
            .padding(.horizontal, DS.xl)
        }
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                isDragging = true
                dragProgress = min(max(0, v.location.x / width), 1)
            }
            .onEnded { v in
                let p = min(max(0, v.location.x / width), 1)
                player.seek(seconds: p * player.durationSeconds)
                isDragging = false
            }
    }

    // MARK: Control Row (shuffle/prev/PLAY/next/repeat)

    private var controlRow: some View {
        HStack(spacing: 0) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                queue.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(queue.shuffle ? DS.accent : DS.textSecondary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task { if let prev = queue.rewind() { await player.play(trackId: prev.id) } }
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(DS.textPrimary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle().fill(DS.textPrimary).frame(width: 72, height: 72)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(.black)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task { if let next = queue.advance() { await player.play(trackId: next.id) } }
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(DS.textPrimary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                queue.cycleRepeat()
            } label: {
                Image(systemName: repeatIcon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(queue.repeatMode == .off ? DS.textSecondary : DS.accent)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.l)
    }

    private var repeatIcon: String {
        switch queue.repeatMode {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    // MARK: Bottom (device/share/queue)

    private var bottomActions: some View {
        HStack(spacing: 28) {
            Button { } label: {
                Image(systemName: "hifispeaker.and.homepod.mini")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button { } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
            }
            .buttonStyle(.plain)

            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Lyrics Peek-Card

    private var lyricsCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Lyrics")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DS.textPrimary)
                Text("Lyrics folgen bald...")
                    .font(.system(size: 14))
                    .foregroundStyle(DS.textSecondary.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer()
            HStack(spacing: DS.m) {
                Image(systemName: "square.and.arrow.up").foregroundStyle(DS.textSecondary)
                Image(systemName: "arrow.up.left.and.arrow.down.right").foregroundStyle(DS.textSecondary)
            }
            .font(.system(size: 15, weight: .semibold))
        }
        .padding(DS.l)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous))
    }

    // MARK: Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [DS.bgElevated, DS.bg],
            startPoint: .top, endPoint: .bottom
        )
    }
}
