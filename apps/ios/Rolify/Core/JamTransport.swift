import Foundation

/// Gemeinsame Abstraktion fuer Jam-Transport — erlaubt WebSocket (JamClient) und
/// Bluetooth/WiFi-Direct (JamLocalTransport via MultipeerConnectivity) dieselbe
/// Protocol-API zu nutzen.
///
/// Protocol-Messages sind JSON-encoded:
///   {type: "track_change", trackId, positionMs}
///   {type: "control", action: "play"|"pause", positionMs}
///   {type: "seek", positionMs}
///   {type: "reaction", emoji}
///   {type: "hello", token}  (nur WS)
///   {type: "participants", users}  (vom Server bei WS)
@MainActor
protocol JamTransport: AnyObject {
    /// true wenn Verbindung offen und handshake abgeschlossen
    var isConnected: Bool { get }

    /// Sendet Raw-Message (muss JSON-serialisierbares dict sein)
    func send(_ payload: [String: Any]) async

    /// Startet die Verbindung. Fuer WS: URL + auth-token. Fuer MC: service-discovery.
    func start() async

    /// Trennt sauber und released resources
    func stop()

    /// Callback fuer eingehende Messages. Wird auf MainActor gefeuert.
    var onMessage: (@MainActor (_ payload: [String: Any]) -> Void)? { get set }

    /// Callback fuer State-Change (connected/disconnected/error).
    var onStateChange: (@MainActor (_ connected: Bool) -> Void)? { get set }
}
