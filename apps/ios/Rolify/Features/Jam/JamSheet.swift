import SwiftUI

/// Hauptsheet fuer Jam. Wenn keine aktive Session: Join/Create-Buttons.
/// Wenn aktiv: Participants-Liste + Share-Code + Leave-Button + Reactions.
struct JamSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var api = API.shared
    @State private var jam = JamOrchestrator.shared

    @State private var joinCode = ""
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()
            content
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        if let code = jam.activeCode, jam.isConnected {
            activeSession(code: code)
        } else {
            entryScreen
        }
    }

    @State private var showBtBrowser = false

    private var entryScreen: some View {
        ScrollView {
            VStack(spacing: DS.xl) {
                header(title: "Jam")

                Spacer().frame(height: DS.s)

                VStack(spacing: DS.m) {
                    Image(systemName: "wifi")
                        .font(.system(size: 44, weight: .black))
                        .foregroundStyle(DS.accent)
                    Text("Hoere live zusammen")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(DS.textPrimary)
                    Text("Online via Code oder lokal via Bluetooth")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.xxl)
                }
                .padding(.vertical, DS.l)

                // === ONLINE-JAM ===
                VStack(spacing: DS.s) {
                    Text("Online (Internet)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DS.xl)

                    Button {
                        Task { await startNew() }
                    } label: {
                        actionRowLabel(icon: "plus.circle.fill", text: "Online-Jam starten", primary: true)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DS.xl)
                    .disabled(isLoading)

                    VStack(alignment: .leading, spacing: DS.xs) {
                        Text("Oder Code eingeben")
                            .font(DS.Font.footnote)
                            .foregroundStyle(DS.textSecondary)
                        HStack {
                            TextField("XXXXXX", text: $joinCode)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundStyle(DS.textPrimary)
                                .padding(.horizontal, DS.l)
                                .frame(height: 44)
                                .background(DS.bgElevated)
                                .clipShape(RoundedRectangle(cornerRadius: DS.radiusM, style: .continuous))
                            Button("Joinen") {
                                Task { await joinExisting() }
                            }
                            .foregroundStyle(joinCode.count >= 4 ? DS.accent : DS.textTertiary)
                            .disabled(joinCode.count < 4 || isLoading)
                        }
                    }
                    .padding(.horizontal, DS.xl)
                    .padding(.top, DS.s)
                }

                Divider().background(DS.divider).padding(.horizontal, DS.xl)

                // === BLUETOOTH-JAM ===
                VStack(spacing: DS.s) {
                    Text("Nearby (Bluetooth / WiFi-Direct)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DS.xl)

                    Button {
                        Task { await startBluetoothHost() }
                    } label: {
                        actionRowLabel(icon: "dot.radiowaves.left.and.right", text: "Nearby-Jam starten (Host)", primary: false)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DS.xl)
                    .disabled(isLoading)

                    Button {
                        Task { await startBluetoothGuest() }
                        showBtBrowser = true
                    } label: {
                        actionRowLabel(icon: "magnifyingglass", text: "Nearby beitreten", primary: false)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DS.xl)
                    .disabled(isLoading)

                    Text("Kein Internet noetig — 2 iPhones im gleichen Raum")
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.xxl)
                }

                if let error {
                    Text(error).font(DS.Font.footnote).foregroundStyle(.red).padding(.horizontal, DS.xl)
                }
                if isLoading { ProgressView().tint(DS.accent) }

                Spacer().frame(height: 40)
            }
            .padding(.top, DS.l)
        }
        .sheet(isPresented: $showBtBrowser) {
            BluetoothBrowserSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func actionRowLabel(icon: String, text: String, primary: Bool) -> some View {
        HStack(spacing: DS.s) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
            Text(text)
                .font(.system(size: 15, weight: .bold))
            Spacer()
        }
        .foregroundStyle(primary ? .black : DS.textPrimary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.l)
        .frame(height: 52)
        .background(primary ? DS.accent : DS.bgElevated)
        .clipShape(Capsule())
    }

    private func startBluetoothHost() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        let me = (try? await api.me())?.displayName ?? "Host"
        await jam.startBluetoothHost(displayName: me)
    }

    private func startBluetoothGuest() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        let me = (try? await api.me())?.displayName ?? "Guest"
        _ = await jam.startBluetoothGuest(displayName: me)
    }

    private func activeSession(code: String) -> some View {
        VStack(spacing: 0) {
            header(title: "Jam")

            ScrollView {
                VStack(spacing: DS.l) {
                    // Code-Card
                    VStack(spacing: DS.s) {
                        Text("Dein Jam-Code")
                            .font(DS.Font.footnote)
                            .foregroundStyle(DS.textSecondary)
                        Text(code)
                            .font(.system(size: 48, weight: .black, design: .monospaced))
                            .foregroundStyle(DS.textPrimary)
                            .tracking(4)
                        Button {
                            UIPasteboard.general.string = code
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } label: {
                            Label("Code kopieren", systemImage: "doc.on.doc")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(DS.accent)
                        }
                    }
                    .padding(DS.l)
                    .frame(maxWidth: .infinity)
                    .background(DS.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous))
                    .padding(.horizontal, DS.xl)

                    // Participants
                    VStack(alignment: .leading, spacing: DS.s) {
                        Text("Dabei (\(jam.client.participants.count))")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(DS.textPrimary)
                        ForEach(jam.client.participants) { p in
                            HStack(spacing: DS.m) {
                                ZStack {
                                    Circle().fill(LinearGradient(
                                        colors: [DS.accentBright, DS.accentDeep],
                                        startPoint: .top, endPoint: .bottom))
                                        .frame(width: 36, height: 36)
                                    Text(initials(p.displayName))
                                        .font(.system(size: 13, weight: .black))
                                        .foregroundStyle(.white)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.displayName)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(DS.textPrimary)
                                    if p.id == jam.client.hostUserId {
                                        Text("Host")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(DS.accent)
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, DS.xl)

                    // Reactions
                    VStack(alignment: .leading, spacing: DS.s) {
                        Text("Reagieren")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(DS.textPrimary)
                        HStack(spacing: DS.m) {
                            ForEach(["🔥", "❤️", "😂", "🎵", "👏"], id: \.self) { emoji in
                                Button { Task { await jam.client.sendReaction(emoji: emoji) } } label: {
                                    Text(emoji).font(.system(size: 32))
                                        .frame(width: 56, height: 56)
                                        .background(DS.bgElevated)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, DS.xl)

                    // Leave/End
                    Button {
                        Task { await endOrLeave() }
                    } label: {
                        Text(jam.client.isHost ? "Session beenden" : "Verlassen")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.red)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(DS.bgElevated)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DS.xl)
                    .padding(.top, DS.l)

                    Spacer().frame(height: 40)
                }
                .padding(.top, DS.l)
            }
        }
    }

    private func header(title: String) -> some View {
        HStack {
            Button("Schliessen") { dismiss() }
                .foregroundStyle(DS.textSecondary)
            Spacer()
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DS.textPrimary)
            Spacer()
            Color.clear.frame(width: 80)
        }
        .padding(.horizontal, DS.l)
        .padding(.top, DS.l)
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    private func startNew() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let me = try await api.me()
            let created = try await api.createJam(name: nil, trackId: Player.shared.currentTrack?.trackId)
            await jam.connect(code: created.code, asHost: true, myUserId: me.id)
        } catch { self.error = error.localizedDescription }
    }

    private func joinExisting() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        let code = joinCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        do {
            let joined = try await api.joinJam(code: code)
            let me = try await api.me()
            await jam.connect(code: joined.code, asHost: joined.hostUserId == me.id, myUserId: me.id)
            if let trackId = joined.currentTrackId {
                await Player.shared.play(trackId: trackId)
            }
        } catch { self.error = error.localizedDescription }
    }

    private func endOrLeave() async {
        guard let code = jam.activeCode else { return }
        do {
            if jam.client.isHost {
                try await api.endJam(code: code)
            } else {
                try await api.leaveJam(code: code)
            }
        } catch {}
        jam.disconnect()
        dismiss()
    }
}

/// Process-wide Singleton der die aktive Jam-Session haelt.
/// Dadurch ueberlebt Jam das Sheet-dismissen (MiniPlayer-like).
@Observable
@MainActor
final class JamOrchestrator {
    static let shared = JamOrchestrator()

    enum Mode { case wireguard, bluetooth }

    let client = JamClient()
    private(set) var activeCode: String?
    private(set) var mode: Mode = .wireguard
    private(set) var localTransport: JamLocalTransport?
    private(set) var isBluetoothHost: Bool = false

    var isConnected: Bool {
        switch mode {
        case .wireguard:
            if case .connected = client.state { return true }
            return false
        case .bluetooth:
            return localTransport?.isConnected ?? false
        }
    }

    init() {
        // WG-Mode Hooks
        client.onTrackChange = { [weak self] trackId, _ in
            guard let self, !self.client.isHost else { return }
            Task { @MainActor in await Player.shared.play(trackId: trackId) }
        }
        client.onControlChange = { [weak self] action, _ in
            guard let self, !self.client.isHost else { return }
            Task { @MainActor in
                switch action {
                case .play: if !Player.shared.isPlaying { Player.shared.togglePlayPause() }
                case .pause: if Player.shared.isPlaying { Player.shared.togglePlayPause() }
                }
            }
        }
        client.onSeek = { [weak self] ms in
            guard let self, !self.client.isHost else { return }
            Task { @MainActor in Player.shared.seek(seconds: Double(ms) / 1000.0) }
        }
    }

    // MARK: WireGuard / Internet

    func connect(code: String, asHost: Bool, myUserId: String) async {
        mode = .wireguard
        activeCode = code
        await client.connect(code: code, asHost: asHost, myUserId: myUserId)
    }

    // MARK: Bluetooth / MultipeerConnectivity

    func startBluetoothHost(displayName: String) async {
        mode = .bluetooth
        isBluetoothHost = true
        activeCode = "BT: \(displayName)"
        let transport = JamLocalTransport(displayName: displayName, role: .host)
        wireBtHandlers(transport)
        await transport.start()
        self.localTransport = transport
    }

    func startBluetoothGuest(displayName: String) async -> JamLocalTransport {
        mode = .bluetooth
        isBluetoothHost = false
        let transport = JamLocalTransport(displayName: displayName, role: .guest)
        wireBtHandlers(transport)
        await transport.start()
        self.localTransport = transport
        return transport
    }

    private func wireBtHandlers(_ transport: JamLocalTransport) {
        transport.onMessage = { [weak self] payload in
            guard let self, !self.isBluetoothHost else { return }
            let type = payload["type"] as? String ?? ""
            switch type {
            case "track_change":
                if let tid = payload["trackId"] as? String {
                    Task { @MainActor in await Player.shared.play(trackId: tid) }
                }
            case "control":
                let action = payload["action"] as? String ?? "pause"
                Task { @MainActor in
                    if action == "play" && !Player.shared.isPlaying { Player.shared.togglePlayPause() }
                    else if action == "pause" && Player.shared.isPlaying { Player.shared.togglePlayPause() }
                }
            case "seek":
                if let pos = payload["positionMs"] as? Int {
                    Task { @MainActor in Player.shared.seek(seconds: Double(pos) / 1000.0) }
                }
            default: break
            }
        }
        transport.onStateChange = { [weak self] connected in
            guard let self else { return }
            if !connected && self.mode == .bluetooth {
                self.activeCode = nil
            }
        }
    }

    /// Convenience-Send fuer BT-Host (nutzt das gleiche Protocol wie WS).
    func btSendTrackChange(trackId: String, positionMs: Int = 0) async {
        guard mode == .bluetooth, isBluetoothHost, let t = localTransport else { return }
        await t.send(["type": "track_change", "trackId": trackId, "positionMs": positionMs])
    }

    func btSendControl(playing: Bool, positionMs: Int) async {
        guard mode == .bluetooth, isBluetoothHost, let t = localTransport else { return }
        await t.send(["type": "control", "action": playing ? "play" : "pause", "positionMs": positionMs])
    }

    func btSendSeek(positionMs: Int) async {
        guard mode == .bluetooth, isBluetoothHost, let t = localTransport else { return }
        await t.send(["type": "seek", "positionMs": positionMs])
    }

    // MARK: Disconnect

    func disconnect() {
        switch mode {
        case .wireguard: client.disconnect()
        case .bluetooth:
            localTransport?.stop()
            localTransport = nil
        }
        activeCode = nil
    }
}
