import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var results: SearchResponse?
    @State private var isLoading = false
    @State private var error: String?
    @State private var debounceTask: Task<Void, Never>?
    @State private var api = API.shared
    @State private var player = Player.shared

    private let browseCategories: [(String, Color)] = [
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
                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    results = nil; error = nil; isLoading = false
                    return
                }
                await runSearch(newValue)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Text("Suche")
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.textPrimary)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            browseGrid
        } else if isLoading && results == nil {
            ProgressView().tint(DS.accent).frame(maxHeight: .infinity)
        } else if let error {
            ErrorView(message: error) {
                Task { await runSearch(query) }
            }
        } else if let results {
            resultsView(results)
        } else {
            Color.clear
        }
    }

    private var browseGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.l) {
                Text("Durchsuche Kategorien")
                    .font(DS.Font.title)
                    .foregroundStyle(DS.textPrimary)
                    .padding(.horizontal, DS.xl)
                    .padding(.top, DS.l)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.m), GridItem(.flexible(), spacing: DS.m)], spacing: DS.m) {
                    ForEach(browseCategories, id: \.0) { (name, color) in
                        categoryCard(name: name, color: color)
                    }
                }
                .padding(.horizontal, DS.xl)

                Spacer().frame(height: 120)
            }
        }
    }

    private func categoryCard(name: String, color: Color) -> some View {
        ZStack(alignment: .topLeading) {
            color
            Text(name)
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(.white)
                .padding(DS.m)
        }
        .frame(height: 100)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusM, style: .continuous))
    }

    @ViewBuilder
    private func resultsView(_ r: SearchResponse) -> some View {
        if r.tracks.isEmpty && r.artists.isEmpty && r.albums.isEmpty {
            VStack(spacing: DS.m) {
                Spacer().frame(height: 80)
                Image(systemName: "magnifyingglass").font(.system(size: 40)).foregroundStyle(DS.textSecondary)
                Text("Nichts gefunden").font(DS.Font.bodyLarge).foregroundStyle(DS.textPrimary)
                Text("Fuer \"\(query)\"").font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !r.tracks.isEmpty {
                        SectionHeader(title: "Songs")
                        ForEach(r.tracks) { t in
                            TrackRow(
                                track: t,
                                isCurrent: player.currentTrack?.trackId == t.id,
                                isPlaying: player.isPlaying && player.currentTrack?.trackId == t.id
                            ) {
                                Task { await player.play(trackId: t.id) }
                            }
                        }
                    }
                    if !r.artists.isEmpty {
                        SectionHeader(title: "Kuenstler")
                        ForEach(r.artists) { a in
                            artistRow(a)
                        }
                    }
                    if !r.albums.isEmpty {
                        SectionHeader(title: "Alben")
                        ForEach(r.albums) { alb in
                            albumRow(alb)
                        }
                    }
                    Spacer().frame(height: 120)
                }
            }
        }
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
}
