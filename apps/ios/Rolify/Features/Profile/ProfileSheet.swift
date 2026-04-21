import SwiftUI

/// Spotify-style Profile-Menu (slide-in von links).
/// Zeigt Avatar + Username + View-Profile + Account-Optionen + Settings.
struct ProfileSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var api = API.shared
    @State private var profile: UserProfile?
    @State private var showScraper = false

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Avatar + Name + Activity-off Button
                HStack(spacing: DS.m) {
                    ZStack {
                        Circle().fill(DS.bgElevated).frame(width: 56, height: 56)
                        if let url = profile?.avatarUrl, !url.isEmpty {
                            AsyncImage(url: URL(string: url)) { img in
                                img.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: { Color.clear }
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                        } else {
                            Text(String((profile?.displayName ?? "?").prefix(1)).uppercased())
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(LinearGradient(
                                    colors: [DS.accent, DS.accentDeep],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                                .clipShape(Circle())
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile?.displayName ?? "...")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(DS.textPrimary)
                        Text("Profil ansehen")
                            .font(.system(size: 13))
                            .foregroundStyle(DS.textSecondary)
                    }

                    Spacer()

                    Button {
                        // TODO: activity toggle
                    } label: {
                        Text("Aktivität aus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.textSecondary)
                            .padding(.horizontal, DS.m)
                            .padding(.vertical, DS.s)
                            .overlay(
                                Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, DS.l)
                .padding(.top, DS.xl)
                .padding(.bottom, DS.l)

                Divider().background(DS.divider)

                // Menu items
                VStack(alignment: .leading, spacing: 0) {
                    menuRow(icon: "plus.circle", title: "Konto hinzufuegen")
                    menuRow(icon: "star.fill", title: "Dein Abo", trailingBadge: "Free", iconFill: DS.accent)
                    menuRow(icon: "chart.line.uptrend.xyaxis", title: "Listening Stats")
                    menuRow(icon: "clock", title: "Recents")
                    menuRow(icon: "arrow.down.circle", title: "Musik scrapen", iconFill: DS.accent) {
                        showScraper = true
                    }
                    menuRow(icon: "gearshape", title: "Einstellungen")
                }
                .padding(.top, DS.s)

                Spacer()

                // Logout
                Button {
                    api.logout()
                    dismiss()
                } label: {
                    HStack(spacing: DS.m) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 18))
                        Text("Abmelden")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(DS.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DS.xl)
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showScraper) {
            AdminScrapeSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task { await loadProfile() }
    }

    @ViewBuilder
    private func menuRow(icon: String, title: String, trailingBadge: String? = nil,
                         iconFill: Color = .white,
                         onTap: (() -> Void)? = nil) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap?()
        } label: {
            HStack(spacing: DS.l) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(iconFill)
                    .frame(width: 28)

                Text(title)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(DS.textPrimary)

                Spacer()

                if let trailingBadge {
                    Text(trailingBadge)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, DS.s)
                        .padding(.vertical, 4)
                        .background(Color(red: 1.0, green: 0.76, blue: 0.84))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, DS.l)
            .padding(.vertical, DS.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadProfile() async {
        do { self.profile = try await api.me() } catch { }
    }
}
