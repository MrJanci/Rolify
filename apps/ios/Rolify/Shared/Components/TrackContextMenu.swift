import SwiftUI

/// Context-Menu (lange halten) auf einer TrackRow.
/// Actions: Zu Playlist, Zur Warteschlange, Album/Artist öffnen, Link kopieren.
///
/// Nimmt einen QueueTrack (immutable track-data) + optional albumId/artistId für Navigation.
/// Der QueueTrack wird direkt für "Zur Warteschlange" genutzt - kein API-Call nötig.
struct TrackContextMenu: ViewModifier {
    let queueTrack: QueueTrack
    let artistId: String?
    let albumId: String?
    @Binding var showAddToPlaylist: Bool
    @Binding var pendingTrackId: String
    @Binding var pendingTrackTitle: String

    func body(content: Content) -> some View {
        content.contextMenu {
            Button {
                pendingTrackId = queueTrack.id
                pendingTrackTitle = queueTrack.title
                showAddToPlaylist = true
            } label: {
                Label("Zu Playlist hinzufuegen", systemImage: "text.badge.plus")
            }

            Button {
                PlaybackQueue.shared.appendAtEnd(queueTrack)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: {
                Label("Zur Warteschlange", systemImage: "text.line.last.and.arrowtriangle.forward")
            }

            Divider()

            if let albumId {
                NavigationLink(value: LibraryRoute.album(albumId)) {
                    Label("Album ansehen", systemImage: "square.stack")
                }
            }
            if let artistId {
                NavigationLink(value: LibraryRoute.artist(artistId)) {
                    Label("Kuenstler", systemImage: "person")
                }
            }

            Divider()

            Button {
                UIPasteboard.general.string = "rolify://track/\(queueTrack.id)"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: {
                Label("Link kopieren", systemImage: "link")
            }
        }
    }
}

extension View {
    /// Für TrackListItem (Home, Library, Search)
    func rolifyTrackContextMenu(
        for track: TrackListItem,
        showAddToPlaylist: Binding<Bool>,
        pendingTrackId: Binding<String>,
        pendingTrackTitle: Binding<String>
    ) -> some View {
        self.modifier(TrackContextMenu(
            queueTrack: QueueTrack(track),
            artistId: nil,
            albumId: track.albumId,
            showAddToPlaylist: showAddToPlaylist,
            pendingTrackId: pendingTrackId,
            pendingTrackTitle: pendingTrackTitle
        ))
    }

    /// Für PlaylistTrackItem (in PlaylistDetailView)
    func rolifyTrackContextMenu(
        for track: PlaylistTrackItem,
        showAddToPlaylist: Binding<Bool>,
        pendingTrackId: Binding<String>,
        pendingTrackTitle: Binding<String>
    ) -> some View {
        self.modifier(TrackContextMenu(
            queueTrack: QueueTrack(track),
            artistId: track.artistId,
            albumId: track.albumId,
            showAddToPlaylist: showAddToPlaylist,
            pendingTrackId: pendingTrackId,
            pendingTrackTitle: pendingTrackTitle
        ))
    }

    /// Für AlbumTrackItem (in AlbumDetailView / ArtistDetailView)
    func rolifyTrackContextMenu(
        for track: AlbumTrackItem,
        showAddToPlaylist: Binding<Bool>,
        pendingTrackId: Binding<String>,
        pendingTrackTitle: Binding<String>
    ) -> some View {
        self.modifier(TrackContextMenu(
            queueTrack: QueueTrack(track),
            artistId: track.artistId,
            albumId: track.albumId,
            showAddToPlaylist: showAddToPlaylist,
            pendingTrackId: pendingTrackId,
            pendingTrackTitle: pendingTrackTitle
        ))
    }
}
