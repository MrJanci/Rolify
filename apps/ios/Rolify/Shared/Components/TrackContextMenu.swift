import SwiftUI

/// Context-Menu (lange halten) auf einer TrackRow.
/// Actions: Zu Playlist, Zur Warteschlange, Offline-Toggle, Album/Artist oeffnen, Link kopieren.
struct TrackContextMenu: ViewModifier {
    let queueTrack: QueueTrack
    let artistId: String?
    let albumId: String?
    @Binding var showAddToPlaylist: Bool
    @Binding var pendingTrackId: String
    @Binding var pendingTrackTitle: String
    @State private var cache = OfflineCache.shared

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

            // Offline-Toggle
            if cache.isAvailable(trackId: queueTrack.id) {
                Button(role: .destructive) {
                    Task { await cache.remove(trackId: queueTrack.id) }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("Offline entfernen", systemImage: "checkmark.circle.fill")
                }
            } else {
                Button {
                    Task {
                        do {
                            try await cache.download(trackId: queueTrack.id)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } catch {
                            UINotificationFeedbackGenerator().notificationOccurred(.error)
                        }
                    }
                } label: {
                    Label("Fuer offline runterladen", systemImage: "arrow.down.circle")
                }
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
    /// Einzelner Helper - Caller baut QueueTrack selbst (keine Overload-Ambiguity).
    func rolifyTrackContextMenu(
        queueTrack: QueueTrack,
        artistId: String? = nil,
        albumId: String? = nil,
        showAddToPlaylist: Binding<Bool>,
        pendingTrackId: Binding<String>,
        pendingTrackTitle: Binding<String>
    ) -> some View {
        self.modifier(TrackContextMenu(
            queueTrack: queueTrack,
            artistId: artistId,
            albumId: albumId,
            showAddToPlaylist: showAddToPlaylist,
            pendingTrackId: pendingTrackId,
            pendingTrackTitle: pendingTrackTitle
        ))
    }
}
