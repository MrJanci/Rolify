import SwiftUI
import MultipeerConnectivity

/// Zeigt discovered Nearby-Hosts + invite-on-tap.
/// Wird im Jam-Sheet als Sub-Sheet gezeigt wenn User "Nearby beitreten" tippt.
struct BluetoothBrowserSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var jam = JamOrchestrator.shared
    @State private var peers: [MCPeerID] = []
    @State private var refreshTicker = 0

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            VStack(spacing: DS.l) {
                header

                if peers.isEmpty {
                    VStack(spacing: DS.m) {
                        Spacer().frame(height: 40)
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 44, weight: .black))
                            .foregroundStyle(DS.accent)
                            .symbolEffect(.variableColor.iterative, options: .repeat(.continuous))
                        Text("Suche Nearby-Jams...")
                            .font(DS.Font.bodyLarge)
                            .foregroundStyle(DS.textPrimary)
                        Text("Beide iPhones brauchen Bluetooth + Lokales Netzwerk an")
                            .font(DS.Font.footnote)
                            .foregroundStyle(DS.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DS.xxl)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(peers, id: \.self) { peer in
                                peerRow(peer)
                            }
                        }
                    }
                }
            }
            .padding(.top, DS.l)
        }
        .preferredColorScheme(.dark)
        .task {
            // Poll discoveredPeers every 1s (MC-Delegate ist auf separate thread)
            while !Task.isCancelled {
                self.peers = jam.localTransport?.discoveredPeers ?? []
                refreshTicker += 1
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var header: some View {
        HStack {
            Button("Abbrechen") { dismiss() }
                .foregroundStyle(DS.textSecondary)
            Spacer()
            Text("Nearby-Jams")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DS.textPrimary)
            Spacer()
            Color.clear.frame(width: 80)
        }
        .padding(.horizontal, DS.l)
    }

    private func peerRow(_ peer: MCPeerID) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            jam.localTransport?.inviteGuest(peer)
            dismiss()
        } label: {
            HStack(spacing: DS.m) {
                Image(systemName: "iphone")
                    .font(.system(size: 22))
                    .foregroundStyle(DS.accent)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(peer.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.textPrimary)
                    Text("Tippen zum Beitreten")
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(.horizontal, DS.xl)
            .padding(.vertical, DS.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
