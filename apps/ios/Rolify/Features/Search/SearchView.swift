import SwiftUI

// ActiveDownload-Struct lebt jetzt in Shared/Components/DiscoverTracksSection.swift
// damit AlbumDetailView + ArtistDetailView den gleichen Type nutzen koennen.

struct SearchView: View {
    @State private var query = ""
    @State private var results: SearchResponse?
    @State private var externalResults: [API.ExternalSearchResponse.Hit] = []
    @State private var isLoading = false
    @State private var isLoadingExternal = false
    @State private var error: String?
    @State private var debounceTask: Task<Void, Never>?
    @State private var showAddToPlaylist = false
    @State private var pendingTrackId = ""
    @State private var pendingTrackTitle = ""
    @State private var showProfileSheet = false
    @State private var activeDownloads: [String: ActiveDownload] = [:]
    @State private var pollTasks: [String: Task<Void, Never>] = [:]
    @State private var ytFallbackJobs: [String: String] = [:]   // query -> jobId
    @State private var api = API.shared
    @State private var player = Player.shared

    private let topCategories: [(name: String, color: Color, icon: String)] = [
        ("Musik", Color(red: 0.92, green: 0.29, blue: 0.51), "music.note"),
        ("Podcasts", Color(red: 0.12, green: 0.60, blue: 0.60), "mic.fill"),
        ("Hoerbuecher", Color(red: 0.13, green: 0.22, blue: 0.55), "book.fill"),
        ("Live Events", Color(red: 0.49, green: 0.22, blue: 0.75), "mappin.and.ellipse"),
    ]

    private let genreCategories: [(name: String, color: Color)] = [
        ("Hip-Hop", Color(red: 0.86, green: 0.27, blue: 0.43)),
        ("Pop", Color(red: 0.95, green: 0.52, blue: 0.21)),
        ("Rock", Color(red: 0.60, green: 0.28, blue: 0.81)),
        ("Electronic", Color(red: 0.16, green: 0.60, blue: 0.87)),
        ("Chill", Color(red: 0.20, green: 0.60, blue: 0.48)),
        ("Workout", Color(red: 0.85, green: 0.35, blue: 0.25)),
        ("Focus", Color(red: 0.35, green: 0.42, blue: 0.75)),
        ("Party", Color(red: 0.91, green: 0.41, blue: 0.60)),
    ]

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()
            content
        }
        .navigationDestination(for: LibraryRoute.self) { route in
            switch route {
            case let .album(id): AlbumDetailView(albumId: id)
            case let .artist(id): ArtistDetailView(artistId: id)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Was willst du hoeren?")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .onChange(of: query) { _, newValue in
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                if Task.isCancelled { return }
                let q = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if q.isEmpty {
                    results = nil; externalResults = []; error = nil; isLoading = false
                    return
                }
                // Parallel: lokal + extern
                async let local: Void = runSearch(q)
                async let external: Void = runExternalSearch(q)
                _ = await (local, external)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: DS.m) {
                    AvatarButton { showProfileSheet = true }
                    Text("Suche")
                        .font(DS.Font.title)
                        .foregroundStyle(DS.textPrimary)
                }
            }
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(trackId: pendingTrackId, trackTitle: pendingTrackTitle)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showProfileSheet) {
            ProfileSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onDisappear {
            // Running polls aufraeumen
            for (_, task) in pollTasks { task.cancel() }
            pollTasks.removeAll()
        }
    }

    @ViewBuilder
    private var content: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            browseGrid
        } else if isLoading && results == nil && externalResults.isEmpty {
            ProgressView().tint(DS.accent).frame(maxHeight: .infinity)
        } else if let error {
            ErrorView(message: error) {
                Task {
                    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    async let l: Void = runSearch(q)
                    async let e: Void = runExternalSearch(q)
                    _ = await (l, e)
                }
            }
        } else {
            combinedResults
        }
    }

    // MARK: - Browse-Grid (empty state)

    private var browseGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.xl) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.m), GridItem(.flexible(), spacing: DS.m)], spacing: DS.m) {
                    ForEach(topCategories, id: \.name) { cat in
                        heroTile(name: cat.name, color: cat.color, icon: cat.icon)
                    }
                }
                .padding(.horizontal, DS.l)
                .padding(.top, DS.l)

                VStack(alignment: .leading, spacing: DS.m) {
                    Text("Durchsuche alle")
                        .font(DS.Font.title)
                        .foregroundStyle(DS.textPrimary)
                        .padding(.horizontal, DS.l)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.m), GridItem(.flexible(), spacing: DS.m)], spacing: DS.m) {
                        ForEach(genreCategories, id: \.name) { cat in
                            genreCard(name: cat.name, color: cat.color)
                        }
                    }
                    .padding(.horizontal, DS.l)
                }

                Spacer().frame(height: 140)
            }
        }
    }

    private func heroTile(name: String, color: Color, icon: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            query = name
        } label: {
            ZStack(alignment: .topLeading) {
                color
                Image(systemName: icon)
                    .font(.system(size: 56, weight: .black))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .rotationEffect(.degrees(25))
                    .offset(x: 40, y: 22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .clipped()
                Text(name)
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(.white)
                    .padding(DS.m)
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusM, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func genreCard(name: String, color: Color) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            query = name
        } label: {
            ZStack(alignment: .topLeading) {
                color
                Text(name)
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(.white)
                    .padding(DS.m)
            }
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusM, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Combined Results (local + external)

    @ViewBuilder
    private var combinedResults: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let hasLocal = (results?.tracks.isEmpty == false)
                    || (results?.artists.isEmpty == false)
                    || (results?.albums.isEmpty == false)
                let hasExternal = !externalResults.isEmpty
                let nothingAtAll = !hasLocal && !hasExternal && !isLoadingExternal && results != nil

                if let r = results {
                    if !r.tracks.isEmpty {
                        SectionHeader(title: "In deiner Bibliothek")
                        ForEach(r.tracks) { t in trackRowWithMenu(t, allTracks: r.tracks) }
                    }
                    if !r.artists.isEmpty {
                        SectionHeader(title: "Kuenstler")
                        ForEach(r.artists) { a in artistRow(a) }
                    }
                    if !r.albums.isEmpty {
                        SectionHeader(title: "Alben")
                        ForEach(r.albums) { alb in albumRow(alb) }
                    }
                }

                // External-Section IMMER zeigen — auch wenn lokale Hits da sind +
                // auch wenn Spotify 0 zurueckgibt. Dann YT-Fallback-Button anbieten.
                externalHeader
                if hasExternal {
                    ForEach(externalResults) { hit in externalRow(hit) }
                } else if isLoadingExternal {
                    HStack(spacing: DS.s) {
                        ProgressView().tint(DS.textSecondary).scaleEffect(0.8)
                        Text("Suche im Web...")
                            .font(DS.Font.footnote)
                            .foregroundStyle(DS.textSecondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, DS.l)
                } else {
                    ytFallbackCard
                }
                _ = nothingAtAll  // unused-var quiet

                Spacer().frame(height: 140)
            }
        }
    }

    /// Fallback-Card wenn Spotify keine Hits liefert / API down ist:
    /// User kann mit Tap einen yt-search-Scrape-Job triggern, der Track wird
    /// dann lokal gescrape t und taucht beim naechsten Search-Refresh auf.
    @ViewBuilder
    private var ytFallbackCard: some View {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeJobId = ytFallbackJobs[q]

        VStack(alignment: .leading, spacing: DS.s) {
            HStack(spacing: DS.m) {
                ZStack {
                    Circle().fill(Color.red.opacity(0.18))
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(Color.red.opacity(0.85))
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(activeJobId == nil ? "Auf YouTube suchen lassen" : "Wird gescrape t…")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DS.textPrimary)
                    Text(activeJobId == nil
                         ? "Spotify hat fuer \"\(q)\" keine Treffer. Rolify kann es direkt von YouTube laden."
                         : "Der Worker laed grad runter. Sobald fertig taucht der Track in der Suche auf.")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(3)
                }
                Spacer()
                if activeJobId == nil {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(DS.accent)
                } else {
                    ProgressView().tint(DS.accent)
                }
            }
        }
        .padding(.horizontal, DS.xl)
        .padding(.vertical, DS.m)
        .contentShape(Rectangle())
        .onTapGesture {
            guard activeJobId == nil, !q.isEmpty else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task { await triggerYTFallback(query: q) }
        }
    }

    private func triggerYTFallback(query: String) async {
        do {
            let resp = try await api.enqueueYTSearch(query: query)
            ytFallbackJobs[query] = resp.id
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            // Polling bis DONE → dann re-run lokal-Search damit Tracks erscheinen
            Task { @MainActor in
                for _ in 0..<300 {  // max ~10 min
                    try? await Task.sleep(for: .seconds(2))
                    guard let job = try? await api.scrapeJob(id: resp.id) else { continue }
                    if job.status == "DONE" || job.status == "FAILED" {
                        ytFallbackJobs.removeValue(forKey: query)
                        if job.status == "DONE" {
                            await runSearch(query)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } else {
                            UINotificationFeedbackGenerator().notificationOccurred(.error)
                        }
                        return
                    }
                }
                ytFallbackJobs.removeValue(forKey: query)
            }
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private var externalHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Aus dem Web")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(DS.textPrimary)
                Text("Tippen zum Herunterladen, + fuer Playlist")
                    .font(DS.Font.footnote)
                    .foregroundStyle(DS.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, DS.xl)
        .padding(.top, DS.l)
        .padding(.bottom, DS.s)
    }

    // MARK: - External-Row

    @ViewBuilder
    private func externalRow(_ h: API.ExternalSearchResponse.Hit) -> some View {
        let active = activeDownloads[h.spotifyId]
        let isQueued = active != nil || (h.isQueued && !h.isDownloaded)

        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            if h.isDownloaded, let localId = h.localId {
                let q = [QueueTrack(id: localId, title: h.title, artist: h.artist, coverUrl: h.coverUrl, durationMs: h.durationMs)]
                Task { await player.play(queue: q, startingAt: localId) }
            } else if !isQueued {
                Task { await triggerDownload(h.spotifyId, addToLiked: true) }
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
                            } else if active != nil {
                                // Dimmed during active download
                                Color.black.opacity(0.3)
                                    .clipShape(RoundedRectangle(cornerRadius: DS.radiusS))
                            }
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(h.title)
                            .font(DS.Font.body)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        if let active {
                            downloadStatusLine(active)
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

                    trailingStatusIcon(h, active: active, isQueued: isQueued)
                }
                .padding(.horizontal, DS.xl)
                .padding(.vertical, DS.s)

                // Progress-Bar (unten am Row-Rand)
                if let active {
                    progressBar(active)
                        .padding(.horizontal, DS.xl + 56)  // von Cover-Ende bis right edge
                        .padding(.bottom, 6)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                Task { await triggerDownload(h.spotifyId, addToLiked: true) }
            } label: {
                Label(isQueued ? "Wird geladen..." : "Herunterladen + Liken", systemImage: "heart.circle")
            }
            .disabled(isQueued || h.isDownloaded)

            if h.isDownloaded, let localId = h.localId {
                Button {
                    pendingTrackId = localId
                    pendingTrackTitle = h.title
                    showAddToPlaylist = true
                } label: {
                    Label("Zu Playlist hinzufuegen", systemImage: "text.badge.plus")
                }
            }
        }
    }

    // MARK: - Status-Sub-Views

    @ViewBuilder
    private func downloadStatusLine(_ active: ActiveDownload) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(DS.accent)
            Text(statusText(active))
                .font(DS.Font.footnote)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
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

    @ViewBuilder
    private func trailingStatusIcon(_ h: API.ExternalSearchResponse.Hit, active: ActiveDownload?, isQueued: Bool) -> some View {
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

    private func progressBar(_ active: ActiveDownload) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(DS.divider)
                if let p = active.progress {
                    Capsule().fill(DS.accent)
                        .frame(width: max(4, geo.size.width * CGFloat(p)))
                        .animation(.easeInOut(duration: 0.4), value: p)
                } else {
                    // Indeterminate pulse
                    Capsule().fill(DS.accent.opacity(0.6))
                        .frame(width: max(20, geo.size.width * 0.3))
                        .offset(x: geo.size.width * 0.35)
                        .animation(
                            .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                            value: active.processed
                        )
                }
            }
        }
        .frame(height: 3)
    }

    // MARK: - Download-Trigger + Polling

    /// Startet Download-Job. Optional: nach DONE auto-like (User-Intent wenn single-tap).
    private func triggerDownload(_ spotifyId: String, addToLiked: Bool) async {
        do {
            let resp = try await api.downloadExternalTrack(spotifyId: spotifyId)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

            // Bereits downloaded? dann nur like
            if resp.status == "already_downloaded", let lid = resp.localId {
                if addToLiked { try? await api.likeTrack(lid) }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                await refreshExternalForSpotifyId(spotifyId)
                return
            }

            guard let jobId = resp.jobId else {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return
            }

            // Registriere active download + starte polling
            activeDownloads[spotifyId] = ActiveDownload(
                spotifyId: spotifyId, jobId: jobId,
                status: "QUEUED", processed: 0, total: 0
            )
            startPolling(spotifyId: spotifyId, jobId: jobId, autoLike: addToLiked)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func startPolling(spotifyId: String, jobId: String, autoLike: Bool) {
        pollTasks[spotifyId]?.cancel()
        pollTasks[spotifyId] = Task { @MainActor in
            var attempts = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                attempts += 1
                if attempts > 300 {  // max 10min
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
                    // Refresh external-row (localId wird jetzt gefuellt)
                    await refreshExternalForSpotifyId(spotifyId)
                    if autoLike {
                        if let hit = externalResults.first(where: { $0.spotifyId == spotifyId }),
                           let lid = hit.localId {
                            try? await api.likeTrack(lid)
                        }
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

    /// Re-fetch nur fuer einen spotifyId um localId/isDownloaded/isLiked zu refreshen.
    private func refreshExternalForSpotifyId(_ spotifyId: String) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let hits = try? await api.externalSearch(q: query) {
            // Mergen: aktuelles Ranking behalten (nur die spezifische Row updaten)
            var merged = externalResults
            if let idx = merged.firstIndex(where: { $0.spotifyId == spotifyId }),
               let updated = hits.first(where: { $0.spotifyId == spotifyId }) {
                merged[idx] = updated
                externalResults = merged
            } else {
                externalResults = hits
            }
        }
    }

    // MARK: - Local-Row (alte TrackRow mit Context-Menu)

    private func trackRowWithMenu(_ t: TrackListItem, allTracks: [TrackListItem]) -> some View {
        TrackRow(
            track: t,
            isCurrent: player.currentTrack?.trackId == t.id,
            isPlaying: player.isPlaying && player.currentTrack?.trackId == t.id
        ) {
            let q = allTracks.map { QueueTrack($0) }
            Task { await player.play(queue: q, startingAt: t.id) }
        }
        .rolifyTrackContextMenu(
            queueTrack: QueueTrack(t),
            albumId: t.albumId,
            showAddToPlaylist: $showAddToPlaylist,
            pendingTrackId: $pendingTrackId,
            pendingTrackTitle: $pendingTrackTitle
        )
    }

    private func artistRow(_ artist: ArtistListItem) -> some View {
        NavigationLink(value: LibraryRoute.artist(artist.id)) {
            HStack(spacing: DS.m) {
                CoverImage(url: artist.imageUrl, cornerRadius: 28, placeholder: "person.fill")
                    .frame(width: 56, height: 56)
                Text(artist.name)
                    .font(DS.Font.bodyLarge)
                    .foregroundStyle(DS.textPrimary)
                Spacer()
                Text("Kuenstler")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.textSecondary)
            }
            .padding(.horizontal, DS.xl)
            .padding(.vertical, DS.s)
        }
        .buttonStyle(.plain)
    }

    private func albumRow(_ album: AlbumListItem) -> some View {
        NavigationLink(value: LibraryRoute.album(album.id)) {
            HStack(spacing: DS.m) {
                CoverImage(url: album.coverUrl, cornerRadius: DS.radiusS)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title)
                        .font(DS.Font.bodyLarge)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text("Album · \(album.artist)")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, DS.xl)
            .padding(.vertical, DS.s)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search ops

    private func runSearch(_ q: String) async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let r = try await api.search(q: q)
            self.results = r
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func runExternalSearch(_ q: String) async {
        isLoadingExternal = true
        defer { isLoadingExternal = false }
        do {
            self.externalResults = try await api.externalSearch(q: q)
        } catch {
            // External-Search-Error ist nicht fatal — lokal reicht
            self.externalResults = []
        }
    }
}
