import SwiftUI

struct ProfileView: View {
    @State private var api = API.shared
    @State private var profile: UserProfile?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            if isLoading {
                ProgressView().tint(DS.accent)
            } else if let profile {
                VStack(spacing: DS.xl) {
                    Spacer().frame(height: 32)

                    ZStack {
                        Circle()
                            .fill(DS.bgElevated)
                            .frame(width: 120, height: 120)
                        if let avatarUrl = profile.avatarUrl {
                            CoverImage(url: avatarUrl, cornerRadius: 60)
                                .frame(width: 120, height: 120)
                        } else {
                            Image(systemName: "person.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(DS.textSecondary)
                        }
                    }

                    VStack(spacing: DS.xs) {
                        Text(profile.displayName)
                            .font(DS.Font.headline)
                            .foregroundStyle(DS.textPrimary)
                        Text(profile.email)
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.textSecondary)
                    }

                    Spacer()

                    Button {
                        api.logout()
                    } label: {
                        Text("Abmelden")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(DS.bgElevated)
                            .clipShape(RoundedRectangle(cornerRadius: DS.radiusL, style: .continuous))
                    }
                    .padding(.horizontal, DS.xl)
                    .padding(.bottom, 40)
                }
            } else if let error {
                ErrorView(message: error) { Task { await load() } }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Text("Profil")
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.textPrimary)
            }
        }
        .task { if profile == nil { await load() } }
    }

    private func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            self.profile = try await api.me()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
