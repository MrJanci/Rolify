import SwiftUI

/// Inline-Variante (statt Sub-Sheet) fuer ProfileSheet. Zeigt:
/// - URL-Input (Spotify-Playlist) + YT-Search-Input
/// - Aktive Jobs (RUNNING + QUEUED + PAUSED)
/// - Failed-Jobs auto-collapse (User kann expanden)
struct ScrapingPanel: View {
    @State private var input = ""
    @State private var jobs: [ScrapeJob] = []
    @State private var isSubmitting = false
    @State private var error: String?
    @State private var showFailed = false
    @State private var pollTask: Task<Void, Never>?
    @State private var api = API.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.m) {
            inputSection
            if let error {
                Text(error).font(DS.Font.footnote).foregroundStyle(.red)
                    .padding(.horizontal, DS.l)
            }
            jobsList
        }
        .padding(.vertical, DS.m)
        .task {
            await load()
            startPolling()
        }
        .onDisappear { pollTask?.cancel() }
    }

    // MARK: - Input

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: DS.xs) {
            Text("Spotify-URL oder YouTube-Suche")
                .font(DS.Font.footnote)
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal, DS.l)

            HStack(spacing: DS.s) {
                TextField("playlist-url ODER 'pop hits 2025'", text: $input)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(DS.textPrimary)
                    .padding(.horizontal, DS.m)
                    .frame(height: 42)
                    .background(DS.bg)
                    .clipShape(RoundedRectangle(cornerRadius: DS.radiusS))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button { Task { await submit() } } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: DS.radiusS).fill(canSubmit ? DS.accent : DS.bg)
                            .frame(width: 42, height: 42)
                        if isSubmitting {
                            ProgressView().tint(.black).scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(canSubmit ? .black : DS.textTertiary)
                        }
                    }
                }
                .disabled(!canSubmit || isSubmitting)
            }
            .padding(.horizontal, DS.l)

            Text("Spotify-URL → Playlist scrapen.  Anderer Text → YouTube-Search top 25.")
                .font(.system(size: 10))
                .foregroundStyle(DS.textTertiary)
                .padding(.horizontal, DS.l)
        }
    }

    private var canSubmit: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Jobs-Liste

    @ViewBuilder
    private var jobsList: some View {
        let active = jobs.filter { ["QUEUED", "RUNNING", "PAUSED"].contains($0.status) }
        let done = jobs.filter { $0.status == "DONE" }
        let failed = jobs.filter { $0.status == "FAILED" }

        VStack(alignment: .leading, spacing: 0) {
            if !active.isEmpty {
                miniHeader("Laufend (\(active.count))")
                ForEach(active) { jobRow($0) }
            }
            if !done.isEmpty {
                miniHeader("Fertig (\(done.count))")
                ForEach(done.prefix(5)) { jobRow($0) }
                if done.count > 5 {
                    Text("+ \(done.count - 5) weitere")
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.textTertiary)
                        .padding(.horizontal, DS.l).padding(.bottom, DS.s)
                }
            }
            if !failed.isEmpty {
                Button { withAnimation { showFailed.toggle() } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showFailed ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                        Text("Fehler (\(failed.count))")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(DS.textSecondary)
                    .padding(.horizontal, DS.l).padding(.vertical, DS.s)
                }
                .buttonStyle(.plain)
                if showFailed {
                    ForEach(failed.prefix(10)) { jobRow($0) }
                }
            }
            if jobs.isEmpty {
                Text("Noch keine Jobs.")
                    .font(DS.Font.footnote)
                    .foregroundStyle(DS.textTertiary)
                    .padding(.horizontal, DS.l).padding(.vertical, DS.m)
            }
        }
    }

    private func miniHeader(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, DS.l).padding(.vertical, 6)
    }

    private func jobRow(_ job: ScrapeJob) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: DS.s) {
                statusBadge(for: job.status)
                Text(shortUrl(job.playlistUrl))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Spacer()
            }
            if job.status == "RUNNING" || job.status == "PAUSED" {
                progressBar(for: job)
                Text("\(job.processedTracks)/\(job.totalTracks) · \(job.failedTracks) failed")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.textTertiary)
            } else if job.status == "DONE" {
                Text("\(job.processedTracks)/\(job.totalTracks) Tracks")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.textTertiary)
            } else if let err = job.errorMessage, !err.isEmpty {
                Text(err.prefix(80) + (err.count > 80 ? "…" : ""))
                    .font(.system(size: 9))
                    .foregroundStyle(.red.opacity(0.8))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, DS.l).padding(.vertical, DS.s)
        .contextMenu {
            if job.status == "RUNNING" || job.status == "QUEUED" {
                Button { Task { try? await api.pauseScrapeJob(id: job.id); await load() } } label: {
                    Label("Pausieren", systemImage: "pause.circle")
                }
            }
            if job.status == "PAUSED" {
                Button { Task { try? await api.resumeScrapeJob(id: job.id); await load() } } label: {
                    Label("Fortsetzen", systemImage: "play.circle")
                }
            }
            if ["QUEUED", "PAUSED", "FAILED"].contains(job.status) {
                Button(role: .destructive) {
                    Task { try? await api.cancelScrapeJob(id: job.id); await load() }
                } label: {
                    Label("Loeschen", systemImage: "xmark.circle")
                }
            }
        }
    }

    private func progressBar(for job: ScrapeJob) -> some View {
        GeometryReader { geo in
            let progress = job.totalTracks > 0 ? Double(job.processedTracks) / Double(job.totalTracks) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(DS.bg)
                Capsule().fill(DS.accent).frame(width: max(0, geo.size.width * progress))
            }
            .frame(height: 3)
        }
        .frame(height: 3)
    }

    private func statusBadge(for status: String) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case "QUEUED": return ("Wartet", DS.textSecondary)
            case "RUNNING": return ("Laeuft", DS.accent)
            case "PAUSED": return ("Pause", Color.orange)
            case "DONE": return ("OK", Color.green)
            case "FAILED": return ("Fehler", .red)
            default: return (status, DS.textSecondary)
            }
        }()
        return Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private func shortUrl(_ s: String) -> String {
        if s.hasPrefix("yt:search:") {
            return "🔍 " + String(s.dropFirst("yt:search:".count).prefix(28))
        }
        if s.hasPrefix("yt:playlist:") {
            return "📋 YT " + String(s.dropFirst("yt:playlist:".count).prefix(20))
        }
        if s.hasPrefix("yt:video:") {
            return "▶️ YT " + String(s.dropFirst("yt:video:".count).prefix(15))
        }
        if s.contains("collection") { return "❤️ Liked Songs" }
        if let r = s.range(of: "playlist[:/]", options: .regularExpression) {
            return "🎵 " + String(s[r.upperBound...]).prefix(22) + "…"
        }
        if let r = s.range(of: "track[:/]", options: .regularExpression) {
            return "♪ " + String(s[r.upperBound...]).prefix(15)
        }
        return String(s.prefix(34))
    }

    // MARK: - Actions

    private func submit() async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSubmitting = true; error = nil
        defer { isSubmitting = false }

        // Spotify-URL → playlist scrape, sonst YT-Search
        let urlToSubmit: String
        if trimmed.contains("spotify.com") || trimmed.hasPrefix("spotify:") || trimmed.contains("/track/") {
            urlToSubmit = trimmed
        } else if trimmed.contains("youtube.com/watch") || trimmed.contains("youtu.be/") {
            urlToSubmit = trimmed   // worker dispatcht zu yt:video
        } else if trimmed.contains("youtube.com/playlist") || trimmed.contains("music.youtube.com/playlist") {
            urlToSubmit = trimmed   // worker dispatcht zu yt:playlist
        } else {
            // Plain text → YT-Search-Job
            urlToSubmit = "yt:search:\(trimmed)"
        }

        do {
            _ = try await api.startScrape(playlistUrl: urlToSubmit)
            input = ""
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await load()
        } catch {
            self.error = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func load() async {
        do {
            let resp = try await api.scrapeJobs()
            self.jobs = resp.jobs
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled { return }
                let hasActive = jobs.contains { ["QUEUED", "RUNNING", "PAUSED"].contains($0.status) }
                if hasActive { await load() }
            }
        }
    }
}
