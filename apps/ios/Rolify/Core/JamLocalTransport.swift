import Foundation
import MultipeerConnectivity

/// Bluetooth/WiFi-Direct Jam-Transport via Apple MultipeerConnectivity.
/// 2 iPhones im gleichen Raum discovern sich automatisch (via Bonjour über
/// BT-LowEnergy + WiFi-Direct) — keine Internet-Verbindung nötig.
///
/// Host: ruft `start()` mit role=.host → advertisert als Rolify-Jam-Host
/// Guest: ruft `start()` mit role=.guest → browset + connected sich zum Host
///
/// Protocol identisch zum WebSocket (gleiche JSON-Messages), nur Transport ändert sich.
@MainActor
final class JamLocalTransport: NSObject, JamTransport {
    enum Role { case host, guest }

    private static let serviceType = "rolify-jam"

    private let myPeer: MCPeerID
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private let role: Role

    var onMessage: (@MainActor (_ payload: [String: Any]) -> Void)?
    var onStateChange: (@MainActor (_ connected: Bool) -> Void)?
    var onPeerDiscovered: (@MainActor (_ peer: MCPeerID) -> Void)?

    private(set) var isConnected: Bool = false

    /// Discovered peers (nur im guest-Mode relevant).
    private(set) var discoveredPeers: [MCPeerID] = []

    init(displayName: String, role: Role) {
        self.myPeer = MCPeerID(displayName: displayName)
        self.role = role
        super.init()
        self.session = MCSession(peer: myPeer, securityIdentity: nil, encryptionPreference: .required)
        self.session.delegate = self
    }

    func start() async {
        switch role {
        case .host:
            let adv = MCNearbyServiceAdvertiser(
                peer: myPeer,
                discoveryInfo: ["v": "0.16"],
                serviceType: Self.serviceType
            )
            adv.delegate = self
            adv.startAdvertisingPeer()
            self.advertiser = adv
        case .guest:
            let br = MCNearbyServiceBrowser(peer: myPeer, serviceType: Self.serviceType)
            br.delegate = self
            br.startBrowsingForPeers()
            self.browser = br
        }
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        session.disconnect()
        discoveredPeers = []
        isConnected = false
        onStateChange?(false)
    }

    func send(_ payload: [String: Any]) async {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        guard !session.connectedPeers.isEmpty else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    /// Guest-only: mit einem discovered peer verbinden.
    func inviteGuest(_ peer: MCPeerID) {
        guard role == .guest else { return }
        browser?.invitePeer(peer, to: session, withContext: nil, timeout: 10)
    }
}

// MARK: - MCSessionDelegate

extension JamLocalTransport: @preconcurrency MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            let connected = state == .connected
            self.isConnected = connected
            self.onStateChange?(connected)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            self.onMessage?(obj)
        }
    }

    // Ungenutzte Stream/Resource-Callbacks — wir nutzen nur data send/receive
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?) {}
}

// MARK: - Advertiser (host)

extension JamLocalTransport: @preconcurrency MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            // Host accepted invitations automatisch (kein User-Prompt)
            invitationHandler(true, self.session)
        }
    }
}

// MARK: - Browser (guest)

extension JamLocalTransport: @preconcurrency MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        Task { @MainActor in
            if !self.discoveredPeers.contains(peerID) {
                self.discoveredPeers.append(peerID)
            }
            self.onPeerDiscovered?(peerID)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.discoveredPeers.removeAll { $0 == peerID }
        }
    }
}
