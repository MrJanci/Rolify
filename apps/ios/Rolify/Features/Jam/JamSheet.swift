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

    private var entryScreen: some View {
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
                Text("Starte eine Session oder joine via Code")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.xxl)
            }
            .padding(.vertical, DS.l)

            Button {
                Task { await startNew() }
            } label: {
                HStack(spacing: DS.s) {
                    Image(systemName: "plus.circle.fill")
                    Text("Jam starten")
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(DS.accent)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DS.xl)
            .disabled(isLoading)

            VStack(alignment: .leading, spacing: DS.s) {
                Text("Oder Code eingeben")
                    .font(DS.Font.footnote)
                    .foregroundStyle(DS.textSecondary)
                HStack {
                    TextField("XXXXXX", text: $joinCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(DS.textPrimary)
                        .padding(.horizontal, DS.l)
                        .frame(height: 48)
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

            if let error {
                Text(error).font(DS.Font.footnote).foregroundStyle(.red).padding(.horizontal, DS.xl)
            }
            if isLoading { ProgressView().tint(DS.accent) }

            Spacer()
        }
        .padding(.top, DS.l)
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

    let client = JamClient()
    private(set) var activeCode: String?
    var isConnected: Bool {
        if case .connected = client.state { return true }
        return false
    }

    init() {
        // Hook: wenn Host einen Track-Change macht im Player, broadcast an Jam.
        // Fuer einfachheit: wird im JamSheet-Flow direkt gemacht.
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

    func connect(code: String, asHost: Bool, myUserId: String) async {
        activeCode = code
        await client.connect(code: code, asHost: asHost, myUserId: myUserId)
    }

    func disconnect() {
        client.disconnect()
        activeCode = nil
    }
}
