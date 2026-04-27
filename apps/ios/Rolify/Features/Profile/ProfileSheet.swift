import SwiftUI

/// Profil-Sheet als single Place fuer alles: User-Info, Settings, Scraping-Panel,
/// Logout. Keine Sub-Sheets mehr — alles inline-collapsible damit kein
/// Sheet-on-Sheet-Chaos.
struct ProfileSheet: View {
    @Environment(\.dismiss) var dismiss

    @State private var api = API.shared
    @State private var user: UserProfile?
    @State private var isLoading = true
    @State private var error: String?
    @State private var showLogoutConfirm = false

    // Inline-Sektionen (statt Sub-Sheets):
    @State private var expandScraping = false
    @State private var expandSettings = false
    @State private var expandAutoPlaylists = false

    // Settings-State
    @State private var apiBase: String = UserDefaults.standard.string(forKey: "rolify.apiBase") ?? ""
    @State private var crossfadeS: Double = UserDefaults.standard.double(forKey: "rolify.crossfadeSeconds")

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                grabber
                content
            }
        }
        .preferredColorScheme(.dark)
        .alert("Wirklich abmelden?", isPresented: $showLogoutConfirm) {
            Button("Abbrechen", role: .cancel) {}
            Button("Abmelden", role: .destructive) {
                api.logout()
                dismiss()
            }
        } message: {
            Text("Du musst dich danach neu einloggen.")
        }
        .task { if user == nil { await load() } }
    }

    private var grabber: some View {
        Capsule().fill(Color.white.opacity(0.3))
            .frame(width: 36, height: 5)
            .padding(.top, DS.s)
            .padding(.bottom, DS.m)
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: DS.m) {
                // User-Card oder Error-Fallback (mit Logout-Button)
                if let u = user {
                    userCard(u).padding(.horizontal, DS.l)
                } else if isLoading {
                    HStack { Spacer(); ProgressView().tint(DS.accent); Spacer() }
                        .padding(.vertical, DS.xxl)
                } else if let error {
                    VStack(spacing: DS.s) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 28)).foregroundStyle(.red)
                        Text("Profil konnte nicht geladen werden")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DS.textPrimary)
                        Text(error).font(DS.Font.footnote).foregroundStyle(DS.textSecondary)
                            .multilineTextAlignment(.center).padding(.horizontal, DS.xl)
                    }
                    .padding(.vertical, DS.l)
                }

                // Section: Scraping
                sectionWrapper {
                    Button { withAnimation(.easeInOut(duration: 0.2)) { expandScraping.toggle() } } label: {
                        sectionHeader(icon: "arrow.down.circle.fill",
                                       title: "Scraping & Downloads",
                                       expanded: expandScraping)
                    }
                    .buttonStyle(.plain)

                    if expandScraping {
                        Divider().background(DS.divider).padding(.leading, 52)
                        ScrapingPanel()
                    }
                }

                // Section: Auto-Playlists (Last.fm + TikTok dynamic)
                sectionWrapper {
                    Button { withAnimation(.easeInOut(duration: 0.2)) { expandAutoPlaylists.toggle() } } label: {
                        sectionHeader(icon: "sparkles",
                                       title: "Auto-Playlists",
                                       expanded: expandAutoPlaylists)
                    }
                    .buttonStyle(.plain)

                    if expandAutoPlaylists {
                        Divider().background(DS.divider).padding(.leading, 52)
                        AutoPlaylistsPanel()
                    }
                }

                // Section: Einstellungen (mit Crossfade-Slider)
                sectionWrapper {
                    Button { withAnimation(.easeInOut(duration: 0.2)) { expandSettings.toggle() } } label: {
                        sectionHeader(icon: "gearshape.fill",
                                       title: "Einstellungen",
                                       expanded: expandSettings)
                    }
                    .buttonStyle(.plain)

                    if expandSettings {
                        Divider().background(DS.divider).padding(.leading, 52)
                        settingsContent
                    }
                }

                // Section: Logout
                sectionWrapper {
                    Button { showLogoutConfirm = true } label: {
                        HStack(spacing: DS.m) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.red)
                                .frame(width: 24)
                            Text("Abmelden")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.red)
                            Spacer()
                        }
                        .padding(.horizontal, DS.l).padding(.vertical, DS.m)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Text("Rolify v0.16 · Pi-Backend")
                    .font(DS.Font.footnote)
                    .foregroundStyle(DS.textTertiary)
                    .padding(.top, DS.m)

                Spacer().frame(height: DS.xxl)
            }
        }
    }

    // MARK: - Settings Content (inline, ehemals SettingsSheet)

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: DS.l) {
            // Crossfade-Slider
            VStack(alignment: .leading, spacing: DS.xs) {
                HStack {
                    Text("Crossfade")
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.textSecondary)
                    Spacer()
                    Text(crossfadeS == 0 ? "Aus" : "\(Int(crossfadeS))s")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(crossfadeS > 0 ? DS.accent : DS.textTertiary)
                }
                Slider(value: $crossfadeS, in: 0...12, step: 1) { editing in
                    if !editing {
                        UserDefaults.standard.set(crossfadeS, forKey: "rolify.crossfadeSeconds")
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                .tint(DS.accent)
                Text("Sekunden Ueberblendung zwischen Tracks (Spotify-Style). 0 = aus.")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.textTertiary)
            }

            // API-URL
            VStack(alignment: .leading, spacing: DS.xs) {
                Text("API Base-URL")
                    .font(DS.Font.footnote).foregroundStyle(DS.textSecondary)
                TextField("https://rolify.rolak.ch", text: $apiBase)
                    .font(.system(size: 14))
                    .foregroundStyle(DS.textPrimary)
                    .padding(.horizontal, DS.m)
                    .frame(height: 42)
                    .background(DS.bg)
                    .clipShape(RoundedRectangle(cornerRadius: DS.radiusS))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                Text("Leer = Production. LAN-Dev: http://<pi-ip>:3000")
                    .font(DS.Font.footnote).foregroundStyle(DS.textTertiary)
                Button {
                    let trimmed = apiBase.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        UserDefaults.standard.removeObject(forKey: "rolify.apiBase")
                    } else {
                        UserDefaults.standard.set(trimmed, forKey: "rolify.apiBase")
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Text("API-URL speichern")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .background(DS.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.l).padding(.vertical, DS.m)
    }

    // MARK: - Helpers

    private func sectionHeader(icon: String, title: String, expanded: Bool) -> some View {
        HStack(spacing: DS.m) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DS.textPrimary)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DS.textPrimary)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.textTertiary)
                .rotationEffect(.degrees(expanded ? 0 : -90))
        }
        .padding(.horizontal, DS.l).padding(.vertical, DS.m)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func sectionWrapper<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(DS.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous))
            .padding(.horizontal, DS.l)
    }

    private func userCard(_ u: UserProfile) -> some View {
        HStack(spacing: DS.m) {
            ZStack {
                Circle().fill(LinearGradient(
                    colors: [DS.accentBright, DS.accent, DS.accentDeep],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 56, height: 56)
                Text(initials(from: u.displayName))
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(u.displayName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(DS.textPrimary)
                Text(u.email)
                    .font(DS.Font.footnote)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(DS.m)
        .background(DS.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous))
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    private func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do { self.user = try await api.me() } catch { self.error = error.localizedDescription }
    }
}

// SettingsSheet bleibt fuer back-compat (falls noch wo referenced),
// macht aber jetzt nichts mehr — alles inline in ProfileSheet.
struct SettingsSheet: View {
    @Environment(\.dismiss) var dismiss
    var body: some View { Color.clear.onAppear { dismiss() } }
}
