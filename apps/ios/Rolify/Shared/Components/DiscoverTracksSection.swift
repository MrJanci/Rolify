import SwiftUI

/// Live-progress fuer einen laufenden External-Download.
/// Wird sowohl von SearchView als auch DiscoverTracksSection genutzt.
struct ActiveDownload: Hashable {
    let spotifyId: String
    let jobId: String
    var status: String  // QUEUED / RUNNING / DONE / FAILED
    var processed: Int
    var total: Int

    /// 0..1 fuer Progress-Bar. Indeterminate wenn total == 0.
    var progress: Double? {
        guard total > 0 else { return nil }
        return min(1.0, Double(processed) / Double(total))
    }
}

/// Wiederverwendbare Section "Mehr aus dem Web" fuer AlbumDetailView + ArtistDetailView.
/// Zeigt Spotify-Discover-Hits (nicht-gescrape Tracks) + Tap-to-Download mit Live-Progress.
/// Identisches Pattern wie SearchView's externalRow, nur als Component extrahiert.
struct DiscoverTracksSection: View {
    let title: String                    // z.B. "Mehr aus diesem Album" / "Beliebte Tracks"
    let subtitle: String                 // z.B. "Tippen zum Herunterladen"
    let loader: () async throws -> [API.ExternalSearchResponse.Hit]

    @State private var hits: [API.ExternalSearchResponse.Hit] = []
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var activeDownloads: [String: ActiveDownload] = [:]
    @State private var pollTasks: [String: Task<Void, Never>] = [:]
    @State private var api = API.shared
    @State private var player = Player.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !hits.isEmpty {
                header
                ForEach(hits) { hit in row(hit) }
            } else if isLoading {
                HStack(spacing: DS.s) {
                    ProgressView().tint(DS.textSecondary).scaleEffect(0.8)
                    Text("Suche im Web...")
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.textSecondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, DS.l)
            }
        }
        .task { await load() }
        .onDisappear {
            for (_, task) in pollTasks { task.cancel() }
            pollTasks.removeAll()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(DS.textPrimary)
                Text(subtitle)
                    .font(DS.Font.footnote)
                    .foregroundStyle(DS.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, DS.xl)
        .padding(.top, DS.xl)
        .padding(.bottom, DS.s)
    }

    @ViewBuilder
    private func row(_ h: API.ExternalSearchResponse.Hit) -> some View {
        let active = activeDownloads[h.spotifyId]
        let isQueued = active != nil || (h.isQueued && !h.isDownloaded)

        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            if h.isDownloaded, let lid = h.localId {
                let q = [QueueTrack(id: lid, title: h.title, artist: h.artist, coverUrl: h.coverUrl, durationMs: h.durationMs)]
                Task { await player.play(queue: q, startingAt: lid) }
            } else if !isQueued {
                Task { await triggerDownload(h.spotifyId) }
            }
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: DS.m) {
                    CoverImage(url: h.coverUrl, cornerRadius: DS.radiusS)
                        .frame(width: 44, height: 44)
                        .overlay(alignment: .center) {
                            if !h.isDownloaded && !isQueued {
                                ZStack {
                                    Color.black.opacity(0.4)
                                    Image(systemName: "icloud.and.arrow.down")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: DS.radiusS))
                            }
                        }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(h.title)
                            .font(DS.Font.body)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        if let active {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(DS.accent)
                                Text(statusText(active))
                                    .font(DS.Font.footnote)
                                    .foregroundStyle(DS.textSecondary)
                                    .lineLimit(1)
                            }
                        } else {
                            HStack(spacing: 4) {
                                if h.isLiked {
                                    Image(systemName: "heart.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(DS.accent)
                                }
                                Text(h.artist)
                                    .font(DS.Font.footnote)
                                    .foregroundStyle(DS.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer()
                    trailingIcon(h, active: active, isQueued: isQueued)
                }
                .padding(.horizontal, DS.xl)
                .padding(.vertical, DS.s)

                if let active, let p = active.progress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(DS.divider)
                            Capsule().fill(DS.accent)
                                .frame(width: max(4, geo.size.width * CGFloat(p)))
                                .animation(.easeInOut(duration: 0.4), value: p)
                        }
                    }
                    .frame(height: 3)
                    .padding(.horizontal, DS.xl + 56)
                    .padding(.bottom, 6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func trailingIcon(_ h: API.ExternalSearchResponse.Hit, active: ActiveDownload?, isQueued: Bool) -> some View {
        if active != nil || isQueued {
            Circle()
                .stroke(DS.accent.opacity(0.25), lineWidth: 2)
                .overlay {
                    Circle()
                        .trim(from: 0, to: CGFloat(active?.progress ?? 0.15))
                        .stroke(DS.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 18, height: 18)
        } else if h.isDownloaded {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(DS.accent)
        } else {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 20))
                .foregroundStyle(DS.textSecondary)
        }
    }

    private func statusText(_ a: ActiveDownload) -> String {
        switch a.status {
        case "QUEUED": return "In Warteschlange..."
        case "RUNNING":
            if a.total > 0 { return "Lade runter · \(a.processed)/\(a.total)" }
            return "Lade runter..."
        case "DONE": return "Fertig"
        case "FAILED": return "Fehlgeschlagen"
        default: return a.status
        }
    }

    // MARK: - Actions

    private func load() async {
        guard hits.isEmpty && !isLoading else { return }
        isLoading = true; loadFailed = false
        defer { isLoading = false }
        do {
            hits = try await loader()
        } catch {
            loadFailed = true
        }
    }

    private func triggerDownload(_ spotifyId: String) async {
        do {
            let resp = try await api.downloadExternalTrack(spotifyId: spotifyId)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if resp.status == "already_downloaded", let lid = resp.localId {
                try? await api.likeTrack(lid)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                await refreshHit(spotifyId)
                return
            }
            guard let jobId = resp.jobId else {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return
            }
            activeDownloads[spotifyId] = ActiveDownload(
                spotifyId: spotifyId, jobId: jobId,
                status: "QUEUED", processed: 0, total: 0
            )
            startPolling(spotifyId: spotifyId, jobId: jobId)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func startPolling(spotifyId: String, jobId: String) {
        pollTasks[spotifyId]?.cancel()
        pollTasks[spotifyId] = Task { @MainActor in
            var attempts = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                attempts += 1
                if attempts > 300 {
                    activeDownloads.removeValue(forKey: spotifyId)
                    break
                }
                guard let job = try? await api.scrapeJob(id: jobId) else { continue }
                activeDownloads[spotifyId] = ActiveDownload(
                    spotifyId: spotifyId, jobId: jobId,
                    status: job.status,
                    processed: job.processedTracks,
                    total: job.totalTracks
                )
                if job.status == "DONE" {
                    await refreshHit(spotifyId)
                    if let hit = hits.first(where: { $0.spotifyId == spotifyId }), let lid = hit.localId {
                        try? await api.likeTrack(lid)
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    activeDownloads.removeValue(forKey: spotifyId)
                    break
                } else if job.status == "FAILED" {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    activeDownloads.removeValue(forKey: spotifyId)
                    break
                }
            }
            pollTasks.removeValue(forKey: spotifyId)
        }
    }

    private func refreshHit(_ spotifyId: String) async {
        guard let updated = try? await loader() else { return }
        var merged = hits
        if let idx = merged.firstIndex(where: { $0.spotifyId == spotifyId }),
           let hit = updated.first(where: { $0.spotifyId == spotifyId }) {
            merged[idx] = hit
            hits = merged
        }
    }
}
