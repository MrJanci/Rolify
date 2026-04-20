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
    static let bgElevated = Color(red: 0.102, green: 0.102, blue: 0.102)
    static let accent = Color(red: 0.118, green: 0.843, blue: 0.376)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)
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
            Rolify.bg.ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Rolify")
                    .font(.system(size: 48, weight: .black))
                    .foregroundStyle(Rolify.accent)
                    .padding(.top, 60)

                Text(isRegister ? "Konto erstellen" : "Anmelden")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Rolify.textPrimary)

                VStack(spacing: 12) {
                    if isRegister {
                        field(placeholder: "Name", text: $displayName)
                    }
                    field(placeholder: "E-Mail", text: $email, keyboard: .emailAddress)
                    field(placeholder: "Passwort", text: $password, secure: true)
                }
                .padding(.horizontal, 32)

                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    Task { await submit() }
                } label: {
                    Text(isLoading ? "…" : (isRegister ? "Registrieren" : "Einloggen"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Rolify.accent)
                        .clipShape(Capsule())
                }
                .disabled(isLoading)
                .padding(.horizontal, 32)

                Button {
                    isRegister.toggle(); error = nil
                } label: {
                    Text(isRegister ? "Schon registriert? Einloggen" : "Noch kein Konto? Registrieren")
                        .font(.footnote)
                        .foregroundStyle(Rolify.textSecondary)
                }

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
        .foregroundStyle(Rolify.textPrimary)
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Rolify.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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

    var body: some View {
        ZStack {
            Rolify.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if isLoading {
                    ProgressView().tint(Rolify.accent).frame(maxHeight: .infinity)
                } else if let error {
                    Text(error)
                        .foregroundStyle(.red)
                        .padding()
                } else if tracks.isEmpty {
                    Text("Keine Tracks in der Bibliothek")
                        .foregroundStyle(Rolify.textSecondary)
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(tracks) { t in
                                TrackRow(track: t) {
                                    Task { await player.play(trackId: t.id) }
                                }
                            }
                        }
                        .padding(.bottom, 120)
                    }
                }

                Spacer(minLength: 0)
            }

            if player.currentTrack != nil {
                VStack { Spacer(); MiniPlayer() }
            }
        }
        .task {
            await load()
        }
    }

    private var header: some View {
        HStack {
            Text("Library")
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(Rolify.textPrimary)
            Spacer()
            Button {
                api.logout()
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Rolify.textSecondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
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
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: track.coverUrl)) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Rolify.bgElevated)
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Rolify.textPrimary)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(Rolify.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(formatDuration(ms: track.durationMs))
                    .font(.system(size: 12))
                    .foregroundStyle(Rolify.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - MiniPlayer

struct MiniPlayer: View {
    @State private var player = Player.shared

    var body: some View {
        if let track = player.currentTrack {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: track.coverUrl)) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Rectangle().fill(Rolify.bgElevated) }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Rolify.textPrimary).lineLimit(1)
                    Text(track.artist).font(.system(size: 12))
                        .foregroundStyle(Rolify.textSecondary).lineLimit(1)
                }
                Spacer()
                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Rolify.textPrimary)
                }
                Button {
                    player.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Rolify.textSecondary)
                }
            }
            .padding(12)
            .background(Rolify.bgElevated.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
        }
    }
}

func formatDuration(ms: Int) -> String {
    let total = ms / 1000
    let m = total / 60
    let s = total % 60
    return String(format: "%d:%02d", m, s)
}

#Preview {
    ContentView().preferredColorScheme(.dark)
}
