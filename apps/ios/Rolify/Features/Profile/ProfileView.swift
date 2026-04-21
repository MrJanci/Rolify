import SwiftUI

struct ProfileView: View {
    @State private var api = API.shared
    @State private var user: UserProfile?
    @State private var isLoading = true
    @State private var error: String?
    @State private var showAdminSheet = false

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()
            content
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Text("Profil").font(.system(size: 22, weight: .black)).foregroundStyle(DS.textPrimary)
            }
        }
        .sheet(isPresented: $showAdminSheet) {
            AdminScrapeSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task { if user == nil { await load() } }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && user == nil {
            ProgressView().tint(DS.accent).frame(maxHeight: .infinity)
        } else if let error {
            ErrorView(message: error) { Task { await load() } }
        } else if let user {
            ScrollView {
                VStack(spacing: DS.l) {
                    Spacer().frame(height: DS.l)

                    ZStack {
                        Circle().fill(DS.bgElevated)
                            .frame(width: 96, height: 96)
                        Text(initials(from: user.displayName))
                            .font(.system(size: 32, weight: .black))
                            .foregroundStyle(DS.textPrimary)
                    }

                    VStack(spacing: DS.xs) {
                        Text(user.displayName)
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(DS.textPrimary)
                        Text(user.email)
                            .font(.system(size: 14))
                            .foregroundStyle(DS.textSecondary)
                    }

                    VStack(spacing: 0) {
                        Button { showAdminSheet = true } label: {
                            row(icon: "arrow.down.circle.fill", title: "Scraping verwalten")
                        }
                        .buttonStyle(.plain)

                        Divider().background(DS.divider).padding(.leading, 56)

                        Button { api.logout() } label: {
                            row(icon: "rectangle.portrait.and.arrow.right", title: "Abmelden", destructive: true)
                        }
                        .buttonStyle(.plain)
                    }
                    .background(DS.bgElevated)
                    .cornerRadius(DS.radiusM)
                    .padding(.horizontal, DS.l)

                    Spacer().frame(height: 140)
                }
            }
            .refreshable { await load() }
        } else {
            ProgressView().tint(DS.accent).frame(maxHeight: .infinity)
        }
    }

    private func row(icon: String, title: String, destructive: Bool = false) -> some View {
        HStack(spacing: DS.m) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(destructive ? Color.red : DS.textPrimary)
                .frame(width: 28)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(destructive ? Color.red : DS.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.textSecondary)
        }
        .padding(.horizontal, DS.l)
        .padding(.vertical, DS.m)
        .contentShape(Rectangle())
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
