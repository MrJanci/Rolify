import Foundation

/// WebSocket-Client fuer Jam-Sessions. Nutzt URLSessionWebSocketTask.
/// Einfache State-Machine: connecting -> connected -> closed.
@Observable
@MainActor
final class JamClient {
    enum State { case idle, connecting, connected, closed, error(String) }

    private(set) var state: State = .idle
    private(set) var participants: [Participant] = []
    private(set) var isPaused: Bool = false
    private(set) var currentTrackId: String?
    private(set) var positionMs: Int = 0
    private(set) var hostUserId: String?
    private(set) var code: String?
    private(set) var isHost: Bool = false
    private(set) var lastReactions: [Reaction] = []

    var onTrackChange: ((String, Int) -> Void)?  // trackId, positionMs
    var onControlChange: ((ControlAction, Int) -> Void)?
    var onSeek: ((Int) -> Void)?

    struct Participant: Identifiable, Hashable {
        let id: String
        let displayName: String
        let avatarUrl: String?
    }

    struct Reaction: Identifiable, Hashable {
        let id = UUID()
        let userId: String
        let displayName: String
        let emoji: String
        let ts: Date
    }

    enum ControlAction: String { case play, pause }

    private var task: URLSessionWebSocketTask?
    private var api = API.shared

    // MARK: Connect

    func connect(code: String, asHost: Bool, myUserId: String) async {
        self.code = code
        self.isHost = asHost
        self.state = .connecting
        self.hostUserId = nil

        guard var comps = URLComponents(url: api.baseURL, resolvingAgainstBaseURL: false) else {
            state = .error("Base URL invalid"); return
        }
        comps.scheme = (comps.scheme == "https") ? "wss" : "ws"
        comps.path = "/jam/\(code)/ws"
        guard let url = comps.url else { state = .error("Build URL fail"); return }

        let session = URLSession(configuration: .default)
        let t = session.webSocketTask(with: url)
        self.task = t
        t.resume()

        // Hello senden
        guard let token = await api.currentAccessToken() else {
            state = .error("Nicht angemeldet"); return
        }
        let hello: [String: Any] = ["type": "hello", "token": "Bearer \(token)"]
        if let data = try? JSONSerialization.data(withJSONObject: hello),
           let str = String(data: data, encoding: .utf8) {
            try? await t.send(.string(str))
        }

        self.state = .connected
        Task { await self.receiveLoop() }
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        state = .closed
        participants = []
    }

    // MARK: Host-only actions

    func sendTrackChange(trackId: String, positionMs: Int = 0) async {
        guard isHost else { return }
        await send([
            "type": "track_change",
            "trackId": trackId,
            "positionMs": positionMs,
        ])
    }

    func sendPlay(positionMs: Int) async {
        guard isHost else { return }
        await send(["type": "control", "action": "play", "positionMs": positionMs])
    }

    func sendPause(positionMs: Int) async {
        guard isHost else { return }
        await send(["type": "control", "action": "pause", "positionMs": positionMs])
    }

    func sendSeek(positionMs: Int) async {
        guard isHost else { return }
        await send(["type": "seek", "positionMs": positionMs])
    }

    // MARK: Anyone

    func sendReaction(emoji: String) async {
        await send(["type": "reaction", "emoji": emoji])
    }

    // MARK: Private

    private func send(_ payload: [String: Any]) async {
        guard let task else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let str = String(data: data, encoding: .utf8) else { return }
        try? await task.send(.string(str))
    }

    private func receiveLoop() async {
        guard let task else { return }
        while task.state == .running {
            do {
                let msg = try await task.receive()
                switch msg {
                case .string(let s): await handle(raw: s)
                case .data(let d): if let s = String(data: d, encoding: .utf8) { await handle(raw: s) }
                @unknown default: break
                }
            } catch {
                state = .error(error.localizedDescription)
                break
            }
        }
    }

    private func handle(raw: String) async {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        switch type {
        case "state":
            self.hostUserId = obj["hostUserId"] as? String
            self.currentTrackId = obj["currentTrackId"] as? String
            self.positionMs = obj["positionMs"] as? Int ?? 0
            self.isPaused = obj["isPaused"] as? Bool ?? false

        case "participants":
            if let users = obj["users"] as? [[String: Any]] {
                self.participants = users.compactMap { u in
                    guard let id = u["id"] as? String, let name = u["displayName"] as? String else { return nil }
                    return Participant(id: id, displayName: name, avatarUrl: u["avatarUrl"] as? String)
                }
            }

        case "track_change":
            guard let trackId = obj["trackId"] as? String else { return }
            let pos = obj["positionMs"] as? Int ?? 0
            self.currentTrackId = trackId
            self.positionMs = pos
            self.isPaused = false
            onTrackChange?(trackId, pos)

        case "control":
            let action = obj["action"] as? String ?? "pause"
            let pos = obj["positionMs"] as? Int ?? 0
            self.isPaused = (action == "pause")
            self.positionMs = pos
            if let a = ControlAction(rawValue: action) { onControlChange?(a, pos) }

        case "seek":
            let pos = obj["positionMs"] as? Int ?? 0
            self.positionMs = pos
            onSeek?(pos)

        case "reaction":
            guard let userId = obj["userId"] as? String,
                  let emoji = obj["emoji"] as? String else { return }
            let name = obj["displayName"] as? String ?? "?"
            let r = Reaction(userId: userId, displayName: name, emoji: emoji, ts: Date())
            lastReactions.append(r)
            // Keep max 10 reactions floating
            if lastReactions.count > 10 { lastReactions.removeFirst(lastReactions.count - 10) }
            // Auto-remove nach 3s
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                lastReactions.removeAll(where: { $0.id == r.id })
            }

        case "ended":
            state = .closed
            task?.cancel(with: .goingAway, reason: nil)

        default: break
        }
    }
}

// Kleiner Access-Helper fuer den aktuellen Token
extension API {
    func currentAccessToken() async -> String? {
        return accessToken
    }
}
