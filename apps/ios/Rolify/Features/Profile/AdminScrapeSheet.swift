import SwiftUI

struct AdminScrapeSheet: View {
    @Environment(\.dismiss) var dismiss

    @State private var playlistUrl = ""
    @State private var jobs: [ScrapeJob] = []
    @State private var isSubmitting = false
    @State private var isLoading = true
    @State private var error: String?
    @State private var pollTask: Task<Void, Never>?
    @State private var api = API.shared

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                inputSection
                    .padding(.horizontal, DS.xl)
                    .padding(.top, DS.m)

                if let error {
                    Text(error)
                        .font(DS.Font.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, DS.xl)
                        .padding(.top, DS.s)
                }

                Divider().background(DS.divider).padding(.top, DS.xl)

                if isLoading && jobs.isEmpty {
                    ProgressView().tint(DS.accent).frame(maxHeight: .infinity)
                } else if jobs.isEmpty {
                    VStack(spacing: DS.s) {
                        Spacer().frame(height: 40)
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 36))
                            .foregroundStyle(DS.textSecondary)
                        Text("Noch keine Scrape-Jobs")
                            .font(DS.Font.body)
                            .foregroundStyle(DS.textSecondary)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            SectionHeader(title: "Jobs (neueste zuerst)")
                            ForEach(jobs) { job in
                                jobRow(job)
                                Divider().background(DS.divider).padding(.leading, DS.xl)
                            }
                            Spacer().frame(height: 40)
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await load()
            startPolling()
        }
        .onDisappear { pollTask?.cancel() }
    }

    private var header: some View {
        HStack {
            Button("Schliessen") { dismiss() }
                .foregroundStyle(DS.textSecondary)
            Spacer()
            Text("Musik scrapen")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DS.textPrimary)
            Spacer()
            Color.clear.frame(width: 70)
        }
        .padding(.horizontal, DS.l)
        .padding(.top, DS.l)
        .padding(.bottom, DS.m)
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            Text("Spotify-Playlist-URL")
                .font(DS.Font.footnote)
                .foregroundStyle(DS.textSecondary)

            HStack {
                TextField("https://open.spotify.com/playlist/…", text: $playlistUrl)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(DS.textPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, DS.m)
                    .frame(height: 48)
                    .background(DS.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: DS.radiusM, style: .continuous))

                Button {
                    Task { await submit() }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: DS.radiusM, style: .continuous)
                            .fill(isValidUrl ? DS.accent : DS.bgElevated)
                            .frame(width: 48, height: 48)
                        if isSubmitting {
                            ProgressView().tint(.black).scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(isValidUrl ? .black : DS.textTertiary)
                        }
                    }
                }
                .disabled(!isValidUrl || isSubmitting)
            }

            Text("Tipp: Playlist-Share-Link aus Spotify. Nur eigene Playlists (Editorial-Playlists brauchen Extended Quota).")
                .font(.system(size: 11))
                .foregroundStyle(DS.textTertiary)
        }
    }

    private var isValidUrl: Bool {
        let t = playlistUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.contains("spotify.com/playlist/") || t.hasPrefix("spotify:playlist:")
    }

    private func jobRow(_ job: ScrapeJob) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                statusBadge(for: job.status)
                Spacer()
                Text(shortUrl(job.playlistUrl))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
            if job.status == "RUNNING" || job.status == "DONE" || job.status == "PAUSED" {
                progressBar(for: job)
                Text("\(job.processedTracks)/\(job.totalTracks) Tracks · \(job.failedTracks) failed")
                    .font(DS.Font.footnote)
                    .foregroundStyle(DS.textSecondary)
            }
            if let err = job.errorMessage, !err.isEmpty {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, DS.xl)
        .padding(.vertical, DS.m)
        .contextMenu {
            if job.status == "RUNNING" || job.status == "QUEUED" {
                Button {
                    Task { try? await api.pauseScrapeJob(id: job.id); await load() }
                } label: {
                    Label("Pausieren", systemImage: "pause.circle")
                }
            }
            if job.status == "PAUSED" {
                Button {
                    Task { try? await api.resumeScrapeJob(id: job.id); await load() }
                } label: {
                    Label("Fortsetzen", systemImage: "play.circle")
                }
            }
            if job.status == "QUEUED" || job.status == "PAUSED" {
                Button(role: .destructive) {
                    Task { try? await api.cancelScrapeJob(id: job.id); await load() }
                } label: {
                    Label("Abbrechen", systemImage: "xmark.circle")
                }
            }
        }
    }

    private func progressBar(for job: ScrapeJob) -> some View {
        GeometryReader { geo in
            let progress = job.totalTracks > 0 ? Double(job.processedTracks) / Double(job.totalTracks) : 0
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(DS.bgElevated)
                RoundedRectangle(cornerRadius: 2).fill(DS.accent)
                    .frame(width: max(0, geo.size.width * progress))
            }
            .frame(height: 4)
        }
        .frame(height: 4)
    }

    private func statusBadge(for status: String) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case "QUEUED": return ("Wartet", DS.textSecondary)
            case "RUNNING": return ("Laeuft", DS.accent)
            case "PAUSED": return ("Pausiert", Color(red: 0.96, green: 0.62, blue: 0.04))
            case "DONE": return ("Fertig", Color(red: 0.2, green: 0.76, blue: 0.45))
            case "FAILED": return ("Fehler", .red)
            default: return (status, DS.textSecondary)
            }
        }()
        return Text(label)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, DS.s)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private func shortUrl(_ s: String) -> String {
        if let range = s.range(of: "playlist[:/]", options: .regularExpression) {
            return String(s[range.upperBound...]).prefix(22) + "…"
        }
        return String(s.prefix(30))
    }

    // MARK: Actions

    private func submit() async {
        isSubmitting = true; error = nil
        defer { isSubmitting = false }
        do {
            _ = try await api.startScrape(playlistUrl: playlistUrl.trimmingCharacters(in: .whitespacesAndNewlines))
            playlistUrl = ""
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await load()
        } catch {
            self.error = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
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
                let hasActive = jobs.contains { $0.status == "QUEUED" || $0.status == "RUNNING" || $0.status == "PAUSED" }
                if hasActive {
                    await load()
                }
            }
        }
    }
}
