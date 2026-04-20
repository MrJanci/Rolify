import SwiftUI

/// Horizontal-scrolling shelf: tracks / playlists / albums je nach kind.
struct HomeShelfView: View {
    let shelf: HomeShelf
    let player: Player
    @Binding var showAddToPlaylist: Bool
    @Binding var pendingTrackId: String
    @Binding var pendingTrackTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            SectionHeader(title: shelf.title)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.m) {
                    Group {
                        if shelf.kind == "tracks", let tracks = shelf.tracks {
                            ForEach(tracks) { trackCard($0, allTracks: tracks) }
                        } else if shelf.kind == "playlists", let pls = shelf.playlists {
                            ForEach(pls) { playlistCard($0) }
                        } else if shelf.kind == "albums", let albs = shelf.albums {
                            ForEach(albs) { albumCard($0) }
                        }
                    }
                }
                .padding(.horizontal, DS.xl)
            }
        }
    }

    private func trackCard(_ t: TrackListItem, allTracks: [TrackListItem]) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            let q = allTracks.map { QueueTrack($0) }
            Task { await player.play(queue: q, startingAt: t.id) }
        } label: {
            VStack(alignment: .leading, spacing: DS.xs) {
                CoverImage(url: t.coverUrl, cornerRadius: DS.radiusS)
                    .frame(width: 150, height: 150)
                Text(t.title)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .frame(width: 150, alignment: .leading)
                Text(t.artist)
                    .font(DS.Font.footnote)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                    .frame(width: 150, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .rolifyTrackContextMenu(
            trackId: t.id, trackTitle: t.title,
            albumId: t.albumId,
            showAddToPlaylist: $showAddToPlaylist,
            pendingTrackId: $pendingTrackId,
            pendingTrackTitle: $pendingTrackTitle
        )
    }

    private func playlistCard(_ p: PlaylistSummary) -> some View {
        NavigationLink(value: PlaylistRoute.detail(p.id, p.name)) {
            VStack(alignment: .leading, spacing: DS.xs) {
                CoverImage(url: p.coverUrl.isEmpty ? nil : p.coverUrl, cornerRadius: DS.radiusS, placeholder: "music.note.list")
                    .frame(width: 150, height: 150)
                Text(p.name)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .frame(width: 150, alignment: .leading)
                Text("\(p.trackCount) Tracks")
                    .font(DS.Font.footnote)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                    .frame(width: 150, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private func albumCard(_ a: AlbumListItem) -> some View {
        NavigationLink(value: LibraryRoute.album(a.id)) {
            VStack(alignment: .leading, spacing: DS.xs) {
                CoverImage(url: a.coverUrl, cornerRadius: DS.radiusS)
                    .frame(width: 150, height: 150)
                Text(a.title)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                    .frame(width: 150, alignment: .leading)
                Text(a.artist)
                    .font(DS.Font.footnote)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                    .frame(width: 150, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}
