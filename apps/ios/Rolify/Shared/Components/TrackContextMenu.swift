import SwiftUI

/// Extension-basierter contextMenu builder - wiederverwendbar auf jeder TrackRow-Quelle.
/// Usage: `trackRow.rolifyContextMenu(for: track, onNavigate: ...) `
enum TrackContextAction {
    case playNext       // direkt nach current track
    case addToQueue     // ans Ende der Queue
    case addToPlaylist(String)
    case openAlbum(String)
    case openArtist(String)
}

struct TrackContextMenu: ViewModifier {
    let trackId: String
    let trackTitle: String
    let artistId: String?
    let albumId: String?
    @Binding var showAddToPlaylist: Bool
    @Binding var pendingTrackId: String
    @Binding var pendingTrackTitle: String

    func body(content: Content) -> some View {
        content.contextMenu {
            Button {
                pendingTrackId = trackId
                pendingTrackTitle = trackTitle
                showAddToPlaylist = true
            } label: {
                Label("Zu Playlist hinzufuegen", systemImage: "text.badge.plus")
            }

            Button {
                Task { await addToQueue() }
            } label: {
                Label("Zur Warteschlange", systemImage: "text.line.last.and.arrowtriangle.forward")
            }

            if let albumId {
                Divider()
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
                UIPasteboard.general.string = "rolify://track/\(trackId)"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: {
                Label("Link kopieren", systemImage: "link")
            }
        }
    }

    @MainActor
    private func addToQueue() async {
        // Hole stream manifest fuer ein single-track -> append zur Queue
        do {
            let m = try await API.shared.streamManifest(trackId: trackId)
            let qt = QueueTrack(
                id: m.trackId, title: m.title, artist: m.artist,
                coverUrl: m.coverUrl, durationMs: m.durationMs
            )
            PlaybackQueue.shared.appendAtEnd(qt)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

extension View {
    /// Einfacher Helper — braucht bindings fuer die AddToPlaylist-Sheet-Orchestrierung
    func rolifyTrackContextMenu(
        trackId: String,
        trackTitle: String,
        artistId: String? = nil,
        albumId: String? = nil,
        showAddToPlaylist: Binding<Bool>,
        pendingTrackId: Binding<String>,
        pendingTrackTitle: Binding<String>
    ) -> some View {
        self.modifier(TrackContextMenu(
            trackId: trackId, trackTitle: trackTitle,
            artistId: artistId, albumId: albumId,
            showAddToPlaylist: showAddToPlaylist,
            pendingTrackId: pendingTrackId,
            pendingTrackTitle: pendingTrackTitle
        ))
    }
}
