import SwiftUI

struct NowPlayingSheet: View {
    @State private var player = Player.shared
    @State private var queue = PlaybackQueue.shared
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var showQueue = false
    @State private var showJam = false
    @State private var isLiked = false
    @State private var likeChecking = false
    @State private var api = API.shared
    @State private var lastCheckedTrackId: String?
    @State private var showLyrics = false
    @State private var lyricsPreview: String?  // erste plain-Zeile fuer compact-Card

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

                    if let preview = lyricsPreview {
                        lyricsCard(preview: preview, track: track)
                            .padding(.horizontal, DS.xxl)
                            .padding(.bottom, DS.s)
                    }

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
        .sheet(isPresented: $showJam) {
            JamSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showLyrics) {
            if let t = player.currentTrack {
                LyricsView(trackId: t.trackId, title: t.title, artist: t.artist)
            }
        }
        .onChange(of: player.currentTrack?.trackId) { _, newId in
            if let id = newId, id != lastCheckedTrackId {
                lastCheckedTrackId = id
                Task {
                    await refreshLikedStatus(trackId: id)
                    await loadLyricsPreview(trackId: id)
                }
            }
        }
        .task {
            if let id = player.currentTrack?.trackId {
                lastCheckedTrackId = id
                await refreshLikedStatus(trackId: id)
                await loadLyricsPreview(trackId: id)
            }
        }
    }

    private func refreshLikedStatus(trackId: String) async {
        likeChecking = true
        defer { likeChecking = false }
        if let status = try? await api.isTrackLiked(trackId) {
            self.isLiked = status
        }
    }

    private func loadLyricsPreview(trackId: String) async {
        lyricsPreview = nil
        guard let r = try? await api.fetchLyrics(trackId: trackId) else { return }
        // Erste non-empty Zeile als Preview (entweder synced oder plain)
        let text = r.lrcSynced ?? r.plain ?? ""
        let firstLine = text.split(separator: "\n")
            .map { String($0).replacingOccurrences(of: #"\[\d+:\d+(?:\.\d+)?\]"#, with: "", options: .regularExpression) }
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        if let firstLine, !firstLine.isEmpty {
            self.lyricsPreview = firstLine.trimmingCharacters(in: .whitespaces)
        }
    }

    /// Compact-Card (Spotify-Style) — tap → fullscreen LyricsView
    private func lyricsCard(preview: String, track: StreamManifest) -> some View {
        Button { showLyrics = true } label: {
            HStack(alignment: .top, spacing: DS.s) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lyrics")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white.opacity(0.85))
                        .tracking(1)
                    Text(preview)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.up.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(DS.m)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [DS.accentDeep, Color(red: 0.15, green: 0.20, blue: 0.50)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusM, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func toggleLike() {
        guard let id = player.currentTrack?.trackId else { return }
        let wasLiked = isLiked
        // Optimistic UI
        isLiked.toggle()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            do {
                if wasLiked { try await api.unlikeTrack(id) }
                else { try await api.likeTrack(id) }
            } catch {
                // Revert
                await MainActor.run { self.isLiked = wasLiked }
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
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

            Button { toggleLike() } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isLiked ? DS.accent : DS.textSecondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            Menu {
                if let t = player.currentTrack {
                    Button {
                        UIPasteboard.general.string = "rolify://track/\(t.trackId)"
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        Label("Link kopieren", systemImage: "link")
                    }
                    Button {
                        showQueue = true
                    } label: {
                        Label("Warteschlange", systemImage: "list.bullet")
                    }
                    Button {
                        showJam = true
                    } label: {
                        Label("Jam starten", systemImage: "wifi")
                    }
                    Divider()
                    Button(role: .destructive) {
                        player.stop()
                    } label: {
                        Label("Stoppen", systemImage: "stop.circle")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
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

    // MARK: - Bottom actions (AirPlay + Jam + Share + Queue)

    private var bottomActions: some View {
        HStack {
            AirPlayButton(tintColor: UIColor(DS.textSecondary))
                .frame(width: 28, height: 28)

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showJam = true
            } label: {
                Image(systemName: "wifi")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(JamOrchestrator.shared.isConnected ? DS.accent : DS.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer().frame(width: DS.l)

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

            Spacer().frame(width: DS.l)

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
