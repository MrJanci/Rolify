import SwiftUI

struct ContentView: View {
    @State private var api = API.shared

    var body: some View {
        Group {
            if api.isLoggedIn {
                LibraryView()
            } else {
                LoginView()
            }
        }
    }
}

// MARK: - Design Tokens

enum Rolify {
    static let bg = Color(red: 0.071, green: 0.071, blue: 0.071)
    static let bgElevated = Color(red: 0.118, green: 0.118, blue: 0.118)
    static let bgRow = Color(red: 0.094, green: 0.094, blue: 0.094)
    static let accent = Color(red: 0.118, green: 0.843, blue: 0.376)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let divider = Color.white.opacity(0.06)
}

// MARK: - Login

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isRegister = false
    @State private var isLoading = false
    @State private var error: String?
    @State private var api = API.shared

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Rolify.bg], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer().frame(height: 40)

                VStack(spacing: 4) {
                    Text("Rolify")
                        .font(.system(size: 54, weight: .black))
                        .foregroundStyle(Rolify.accent)
                    Text("Your music, your rules.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Rolify.textSecondary)
                }
                .padding(.bottom, 24)

                VStack(spacing: 12) {
                    if isRegister {
                        field(placeholder: "Dein Name", text: $displayName)
                    }
                    field(placeholder: "E-Mail", text: $email, keyboard: .emailAddress)
                    field(placeholder: "Passwort", text: $password, secure: true)
                }
                .padding(.horizontal, 28)

                if let error {
                    Text(error)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 4)
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: 8) {
                        if isLoading { ProgressView().tint(.black).scaleEffect(0.85) }
                        Text(isRegister ? "Registrieren" : "Einloggen")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Rolify.accent)
                    .clipShape(Capsule())
                }
                .disabled(isLoading)
                .padding(.horizontal, 28)
                .padding(.top, 12)

                Button {
                    isRegister.toggle(); error = nil
                } label: {
                    Text(isRegister ? "Schon registriert? Einloggen" : "Noch kein Konto? Registrieren")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Rolify.textSecondary)
                }
                .padding(.top, 4)

                Spacer()
            }
        }
    }

    @ViewBuilder
    private func field(placeholder: String, text: Binding<String>, secure: Bool = false, keyboard: UIKeyboardType = .default) -> some View {
        Group {
            if secure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .keyboardType(keyboard)
                    .autocorrectionDisabled()
            }
        }
        .font(.system(size: 16))
        .foregroundStyle(Rolify.textPrimary)
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background(Rolify.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func submit() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            if isRegister {
                _ = try await api.register(email: email, password: password, displayName: displayName)
            } else {
                _ = try await api.login(email: email, password: password)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Library

struct LibraryView: View {
    @State private var tracks: [TrackListItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var api = API.shared
    @State private var player = Player.shared
    @State private var showNowPlaying = false

    var body: some View {
        ZStack {
            Rolify.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if isLoading {
                    ProgressView().tint(Rolify.accent).frame(maxHeight: .infinity)
                } else if let error {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 32)).foregroundStyle(.red)
                        Text(error).foregroundStyle(Rolify.textPrimary)
                            .multilineTextAlignment(.center).padding(.horizontal)
                        Button("Nochmal") { Task { await load() } }
                            .foregroundStyle(Rolify.accent)
                    }
                    .frame(maxHeight: .infinity)
                } else if tracks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 44, weight: .regular))
                            .foregroundStyle(Rolify.textSecondary)
                        Text("Keine Tracks")
                            .font(.system(size: 15))
                            .foregroundStyle(Rolify.textSecondary)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(tracks) { t in
                                TrackRow(
                                    track: t,
                                    isCurrent: player.currentTrack?.trackId == t.id,
                                    isPlaying: player.isPlaying && player.currentTrack?.trackId == t.id
                                ) {
                                    Task { await player.play(trackId: t.id) }
                                }
                                Divider().background(Rolify.divider).padding(.leading, 88)
                            }
                        }
                        .padding(.bottom, player.currentTrack != nil ? 100 : 24)
                    }
                    .refreshable { await load() }
                }

                Spacer(minLength: 0)
            }

            if player.currentTrack != nil {
                VStack {
                    Spacer()
                    MiniPlayer { showNowPlaying = true }
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView()
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Library")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(Rolify.textPrimary)
                Text("\(tracks.count) Tracks")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Rolify.textSecondary)
            }
            Spacer()
            Button { api.logout() } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Rolify.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(Rolify.bgElevated.opacity(0.7))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let home = try await api.browseHome()
            self.tracks = home.tracks
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - TrackRow

struct TrackRow: View {
    let track: TrackListItem
    let isCurrent: Bool
    let isPlaying: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            onTap()
        }) {
            HStack(spacing: 14) {
                coverImage
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(alignment: .center) {
                        if isCurrent {
                            ZStack {
                                Color.black.opacity(0.45)
                                Image(systemName: isPlaying ? "waveform" : "pause.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(Rolify.accent)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isCurrent ? Rolify.accent : Rolify.textPrimary)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(Rolify.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(formatDuration(ms: track.durationMs))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Rolify.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var coverImage: some View {
        AsyncImage(url: URL(string: track.coverUrl), transaction: Transaction(animation: .easeIn(duration: 0.25))) { phase in
            switch phase {
            case .success(let img):
                img.resizable().aspectRatio(contentMode: .fill)
            case .empty:
                ZStack {
                    Rolify.bgElevated
                    ProgressView().tint(Rolify.textSecondary).scaleEffect(0.6)
                }
            case .failure:
                ZStack {
                    Rolify.bgElevated
                    Image(systemName: "music.note")
                        .foregroundStyle(Rolify.textSecondary)
                }
            @unknown default: Rolify.bgElevated
            }
        }
    }
}

// MARK: - MiniPlayer (bottom bar)

struct MiniPlayer: View {
    @State private var player = Player.shared
    let onTap: () -> Void

    var body: some View {
        if let track = player.currentTrack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onTap()
            } label: {
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: track.coverUrl)) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: { Rolify.bgElevated }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title).font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Rolify.textPrimary).lineLimit(1)
                        Text(track.artist).font(.system(size: 12))
                            .foregroundStyle(Rolify.textSecondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(Rolify.textPrimary)
                            .frame(width: 38, height: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button {
                        player.stop()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Rolify.textSecondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Rolify.bgElevated)
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - NowPlaying full-screen sheet

struct NowPlayingView: View {
    @State private var player = Player.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Rolify.bg.ignoresSafeArea()

            if let track = player.currentTrack {
                VStack(spacing: 0) {
                    Spacer().frame(height: 32)

                    AsyncImage(url: URL(string: track.coverUrl)) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: { Rolify.bgElevated }
                        .frame(width: 320, height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)

                    Spacer().frame(height: 36)

                    VStack(spacing: 6) {
                        Text(track.title)
                            .font(.system(size: 24, weight: .black))
                            .foregroundStyle(Rolify.textPrimary)
                            .multilineTextAlignment(.center)
                        Text(track.artist)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Rolify.textSecondary)
                    }
                    .padding(.horizontal, 24)

                    Spacer().frame(height: 32)

                    VStack(spacing: 6) {
                        GeometryReader { geo in
                            let progress = player.durationSeconds > 0
                                ? player.progressSeconds / player.durationSeconds : 0
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.15))
                                Capsule().fill(Rolify.textPrimary)
                                    .frame(width: max(0, geo.size.width * progress))
                            }
                            .frame(height: 4)
                        }
                        .frame(height: 4)
                        .padding(.horizontal, 24)

                        HStack {
                            Text(formatDuration(seconds: player.progressSeconds))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Rolify.textSecondary)
                            Spacer()
                            Text("-" + formatDuration(seconds: max(0, player.durationSeconds - player.progressSeconds)))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Rolify.textSecondary)
                        }
                        .padding(.horizontal, 24)
                    }

                    Spacer().frame(height: 24)

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 32, weight: .black))
                            .foregroundStyle(.black)
                            .frame(width: 72, height: 72)
                            .background(Circle().fill(Rolify.textPrimary))
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Helpers

func formatDuration(ms: Int) -> String {
    let total = ms / 1000
    let m = total / 60
    let s = total % 60
    return String(format: "%d:%02d", m, s)
}

func formatDuration(seconds: Double) -> String {
    let total = Int(max(0, seconds))
    let m = total / 60
    let s = total % 60
    return String(format: "%d:%02d", m, s)
}

#Preview { ContentView().preferredColorScheme(.dark) }
