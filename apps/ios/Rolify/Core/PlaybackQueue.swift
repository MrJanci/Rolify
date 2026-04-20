import Foundation

/// Universal-Track-Representation fuer die Queue — kann aus
/// TrackListItem, PlaylistTrackItem, AlbumTrackItem konstruiert werden.
struct QueueTrack: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let coverUrl: String
    let durationMs: Int

    init(id: String, title: String, artist: String, coverUrl: String, durationMs: Int) {
        self.id = id
        self.title = title
        self.artist = artist
        self.coverUrl = coverUrl
        self.durationMs = durationMs
    }

    init(_ t: TrackListItem) {
        self.init(id: t.id, title: t.title, artist: t.artist, coverUrl: t.coverUrl, durationMs: t.durationMs)
    }

    init(_ t: PlaylistTrackItem) {
        self.init(id: t.id, title: t.title, artist: t.artist, coverUrl: t.coverUrl, durationMs: t.durationMs)
    }

    init(_ t: AlbumTrackItem) {
        self.init(id: t.id, title: t.title, artist: t.artist, coverUrl: t.coverUrl, durationMs: t.durationMs)
    }
}

enum RepeatMode: String {
    case off, all, one
}

@Observable
@MainActor
final class PlaybackQueue {
    static let shared = PlaybackQueue()

    private(set) var originalOrder: [QueueTrack] = []
    private(set) var order: [QueueTrack] = []  // gleich wie original oder geshuffelt
    private(set) var currentIndex: Int = 0

    var shuffle: Bool = false {
        didSet { if oldValue != shuffle { rebuildOrder() } }
    }
    var repeatMode: RepeatMode = .off

    var currentTrack: QueueTrack? {
        guard order.indices.contains(currentIndex) else { return nil }
        return order[currentIndex]
    }

    var upNext: [QueueTrack] {
        guard currentIndex + 1 < order.count else { return [] }
        return Array(order[(currentIndex + 1)...])
    }

    // MARK: Public API

    func setQueue(_ tracks: [QueueTrack], startingAt trackId: String? = nil) {
        self.originalOrder = tracks
        self.order = tracks
        if let id = trackId, let idx = tracks.firstIndex(where: { $0.id == id }) {
            self.currentIndex = idx
        } else {
            self.currentIndex = 0
        }
        if shuffle { rebuildOrder() }
    }

    /// Kommt vom TimeObserver wenn der Track endet, oder vom Next-Button.
    func advance() -> QueueTrack? {
        guard !order.isEmpty else { return nil }
        switch repeatMode {
        case .one:
            return order[currentIndex]  // selber Track nochmal
        case .all:
            currentIndex = (currentIndex + 1) % order.count
            return order[currentIndex]
        case .off:
            let nextIdx = currentIndex + 1
            if nextIdx < order.count {
                currentIndex = nextIdx
                return order[currentIndex]
            }
            return nil  // Ende der Queue
        }
    }

    func rewind() -> QueueTrack? {
        guard !order.isEmpty else { return nil }
        if currentIndex > 0 {
            currentIndex -= 1
        } else if repeatMode == .all {
            currentIndex = order.count - 1
        } else {
            // Zurueck auf Start des aktuellen Tracks (Standard-Verhalten wie Spotify)
            return order[currentIndex]
        }
        return order[currentIndex]
    }

    func toggleShuffle() {
        shuffle.toggle()
    }

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    func clear() {
        originalOrder = []
        order = []
        currentIndex = 0
    }

    /// Fuegt Track ans Ende der Queue an (Context-Menu "Zur Warteschlange")
    func appendAtEnd(_ track: QueueTrack) {
        // Wenn Track schon in Queue: skip
        guard !order.contains(where: { $0.id == track.id }) else { return }
        originalOrder.append(track)
        order.append(track)
    }

    // MARK: Internal

    private func rebuildOrder() {
        guard !originalOrder.isEmpty else { return }
        // Aktuellen Track merken damit currentIndex korrekt bleibt
        let currentId = order.indices.contains(currentIndex) ? order[currentIndex].id : nil

        if shuffle {
            var shuffled = originalOrder
            shuffled.shuffle()
            // Aktuellen Track an currentIndex lassen -> bewege ihn an position 0 ff.
            if let id = currentId, let idx = shuffled.firstIndex(where: { $0.id == id }) {
                let t = shuffled.remove(at: idx)
                shuffled.insert(t, at: 0)
                currentIndex = 0
            }
            order = shuffled
        } else {
            order = originalOrder
            if let id = currentId, let idx = order.firstIndex(where: { $0.id == id }) {
                currentIndex = idx
            }
        }
    }
}
