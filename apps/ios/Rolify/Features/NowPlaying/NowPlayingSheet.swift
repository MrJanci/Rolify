import SwiftUI

/// Full-screen Now-Playing Sheet (Spotify-style).
struct NowPlayingSheet: View {
    @State private var player = Player.shared
    @State private var queue = PlaybackQueue.shared
    @Environment(\.dismiss) var dismiss
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var showQueue = false

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()
            contentStack
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showQueue) {
            QueueView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var contentStack: some View {
        VStack(spacing: 0) {
            headerRow
                .padding(.horizontal, DS.l)
                .padding(.top, DS.m)

            Spacer().frame(height: DS.xl)
            coverSection
            Spacer().frame(height: 28)

            titleRow
            Spacer().frame(height: DS.xl)

            progressBar
            Spacer().frame(height: 16)

            controlRow
            Spacer().frame(height: DS.xxl)

            bottomActions.padding(.horizontal, DS.xl)

            lyricsCard
                .padding(.top, DS.m)
                .padding(.horizontal, DS.m)
        }
    }

    // MARK: Header

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

            Text("Wird gespielt")
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

    @ViewBuilder
    private var coverSection: some View {
        if let track = player.currentTrack {
            CoverImage(url: track.coverUrl, cornerRadius: DS.radiusM)
                .frame(width: 340, height: 340)
                .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
        } else {
            Color.clear.frame(width: 340, height: 340)
        }
    }

    // MARK: Title + Save

    @ViewBuilder
    private var titleRow: some View {
        if let track = player.currentTrack {
            HStack(alignment: .top, spacing: DS.m) {
                trackTextBlock(track)
                saveCheckBadge
            }
            .padding(.horizontal, DS.xl)
        }
    }

    private func trackTextBlock(_ track: StreamManifest) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: DS.xs) {
                explicitBadge
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
    }

    private var explicitBadge: some View {
        Text("E")
            .font(.system(size: 10, weight: .black))
            .foregroundStyle(DS.textSecondary)
            .frame(width: 16, height: 16)
            .background(Color.white.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var saveCheckBadge: some View {
        ZStack {
            Circle().fill(DS.accent).frame(width: 32, height: 32)
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.black)
        }
    }

    // MARK: Progress

    private var progressBar: some View {
        VStack(spacing: DS.xs) {
            progressBarTrack
                .padding(.horizontal, DS.xl)
            progressLabels
                .padding(.horizontal, DS.xl)
        }
    }

    private var progressBarTrack: some View {
        GeometryReader { geo in
            let actualProgress = player.durationSeconds > 0
                ? player.progressSeconds / player.durationSeconds : 0
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
    }

    private var progressLabels: some View {
        HStack {
            Text(formatDuration(seconds: isDragging ? dragProgress * player.durationSeconds : player.progressSeconds))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(DS.textSecondary)
            Spacer()
            Text("-" + formatDuration(seconds: max(0, player.durationSeconds - player.progressSeconds)))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(DS.textSecondary)
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

    // MARK: Controls

    private var controlRow: some View {
        HStack(spacing: 0) {
            shuffleButton
            prevButton
            playButton
            nextButton
            repeatButton
        }
        .padding(.horizontal, DS.l)
    }

    private var shuffleButton: some View {
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
    }

    private var prevButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task {
                if let prev = queue.rewind() {
                    await player.play(trackId: prev.id)
                }
            }
        } label: {
            Image(systemName: "backward.end.fill")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(DS.textPrimary)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var playButton: some View {
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
    }

    private var nextButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task {
                if let next = queue.advance() {
                    await player.play(trackId: next.id)
                }
            }
        } label: {
            Image(systemName: "forward.end.fill")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(DS.textPrimary)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var repeatButton: some View {
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

    private var repeatIcon: String {
        switch queue.repeatMode {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    // MARK: Bottom actions

    private var bottomActions: some View {
        HStack(spacing: 28) {
            Button { } label: {
                Image(systemName: "hifispeaker")
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

    // MARK: Lyrics Peek

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
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.textSecondary)
        }
        .padding(DS.l)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous))
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [DS.bgElevated, DS.bg],
            startPoint: .top, endPoint: .bottom
        )
    }
}
