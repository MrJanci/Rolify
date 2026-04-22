import SwiftUI

/// Account-Sheet wie Spotify (Top-Right Avatar tippen -> dieses Sheet).
/// Zeigt aktuellen User, plus Account-Management + Admin + Logout.
struct ProfileSheet: View {
    @Environment(\.dismiss) var dismiss

    @State private var api = API.shared
    @State private var user: UserProfile?
    @State private var isLoading = true
    @State private var error: String?
    @State private var showAdminSheet = false
    @State private var showSettingsSheet = false
    @State private var showLogoutConfirm = false

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                grabber
                content
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showAdminSheet) {
            AdminScrapeSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
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
        Capsule()
            .fill(Color.white.opacity(0.3))
            .frame(width: 36, height: 5)
            .padding(.top, DS.s)
            .padding(.bottom, DS.m)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && user == nil {
            ProgressView().tint(DS.accent).frame(maxHeight: .infinity)
        } else if let user {
            ScrollView {
                VStack(spacing: DS.m) {
                    userCard(user)
                        .padding(.horizontal, DS.l)
                        .padding(.bottom, DS.s)

                    menuGroup {
                        menuRow(icon: "arrow.down.circle.fill", title: "Scraping & Downloads") { showAdminSheet = true }
                        menuDivider
                        menuRow(icon: "gearshape.fill", title: "Einstellungen") { showSettingsSheet = true }
                    }

                    menuGroup {
                        menuRow(icon: "rectangle.portrait.and.arrow.right", title: "Abmelden", destructive: true) { showLogoutConfirm = true }
                    }

                    Text("Rolify v0.13 · Pi-Backend")
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.textTertiary)
                        .padding(.top, DS.m)

                    Spacer().frame(height: DS.xxl)
                }
            }
        } else if let error {
            VStack(spacing: DS.l) {
                ErrorView(message: error) { Task { await load() } }
                Button {
                    api.logout()
                    dismiss()
                } label: {
                    Text("Trotzdem abmelden")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.red)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(DS.bgElevated)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DS.xl)
                .padding(.bottom, DS.xxl)
            }
        } else {
            Color.clear
        }
    }

    private func userCard(_ u: UserProfile) -> some View {
        HStack(spacing: DS.m) {
            ZStack {
                Circle().fill(LinearGradient(
                    colors: [DS.accentBright, DS.accent, DS.accentDeep],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
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

    @ViewBuilder
    private func menuGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(DS.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous))
            .padding(.horizontal, DS.l)
    }

    private var menuDivider: some View {
        Divider().background(DS.divider).padding(.leading, 52)
    }

    private func menuRow(icon: String, title: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: DS.m) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(destructive ? Color.red : DS.textPrimary)
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(destructive ? Color.red : DS.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(.horizontal, DS.l)
            .padding(.vertical, DS.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

// MARK: - Small SettingsSheet (API-Base-URL override + App-Info)

struct SettingsSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var apiBase: String = UserDefaults.standard.string(forKey: "rolify.apiBase") ?? ""

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            VStack(spacing: DS.l) {
                header

                VStack(alignment: .leading, spacing: DS.s) {
                    Text("API Base-URL")
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.textSecondary)
                    TextField("https://rolify.rolak.ch", text: $apiBase)
                        .font(.system(size: 15))
                        .foregroundStyle(DS.textPrimary)
                        .padding(.horizontal, DS.l)
                        .frame(height: 48)
                        .background(DS.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: DS.radiusM, style: .continuous))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Text("Leer lassen fuer Production. Fuer LAN-Dev: http://<pi-lan-ip>:3000")
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.textTertiary)
                }
                .padding(.horizontal, DS.xl)

                Button("Speichern & App neu starten") {
                    let trimmed = apiBase.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        UserDefaults.standard.removeObject(forKey: "rolify.apiBase")
                    } else {
                        UserDefaults.standard.set(trimmed, forKey: "rolify.apiBase")
                    }
                    dismiss()
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(DS.accent)
                .clipShape(Capsule())
                .padding(.horizontal, DS.xl)

                Spacer()
            }
            .padding(.top, DS.l)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            Button("Schliessen") { dismiss() }
                .foregroundStyle(DS.textSecondary)
            Spacer()
            Text("Einstellungen")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DS.textPrimary)
            Spacer()
            Color.clear.frame(width: 80)
        }
        .padding(.horizontal, DS.l)
    }
}
