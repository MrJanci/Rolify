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
        // Dedupe: behalte nur ersten Auftritt pro id (sonst Shuffle-Doppelte-Bug)
        var seen = Set<String>()
        let unique = tracks.filter { seen.insert($0.id).inserted }
        self.originalOrder = unique
        self.order = unique
        if let id = trackId, let idx = unique.firstIndex(where: { $0.id == id }) {
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

    /// Fuegt Track direkt nach dem aktuellen ans Up-Next der Queue an
    /// (Spotify "Add to Queue"-Pattern: gehoert zum Up-Next-Pool, nicht ans Ende).
    /// Wenn Track schon weiter unten ist: bleibt er da, wird aber explizit doppelt
    /// an currentIndex+1 eingefuegt (Spotify behaviour — User will JETZT diesen Song als naechstes).
    func appendAtEnd(_ track: QueueTrack) {
        // Wenn Queue leer: setQueue mit nur diesem Track + currentIndex 0
        if order.isEmpty {
            originalOrder = [track]
            order = [track]
            currentIndex = 0
            return
        }
        // Insert direkt nach current — das ist "Up Next"
        let insertIdx = min(currentIndex + 1, order.count)
        order.insert(track, at: insertIdx)
        // originalOrder synchronisieren (auch dort an gleicher Position)
        if shuffle {
            originalOrder.append(track)  // bei shuffle merken wir's hinten — order ist sowieso schon mixed
        } else {
            originalOrder.insert(track, at: insertIdx)
        }
    }

    // MARK: Internal

    private func rebuildOrder() {
        guard !originalOrder.isEmpty else { return }
        // Defensive Dedupe — falls originalOrder durch externe appends doppelt wurde
        var seen = Set<String>()
        let uniqueSrc = originalOrder.filter { seen.insert($0.id).inserted }

        // Aktuellen Track merken damit currentIndex korrekt bleibt
        let currentId = order.indices.contains(currentIndex) ? order[currentIndex].id : nil

        if shuffle {
            var shuffled = uniqueSrc
            shuffled.shuffle()
            // Aktuellen Track an position 0 — restlich shuffled drumrum.
            if let id = currentId, let idx = shuffled.firstIndex(where: { $0.id == id }) {
                let t = shuffled.remove(at: idx)
                shuffled.insert(t, at: 0)
                currentIndex = 0
            }
            order = shuffled
        } else {
            order = uniqueSrc
            if let id = currentId, let idx = order.firstIndex(where: { $0.id == id }) {
                currentIndex = idx
            }
        }
    }
}
