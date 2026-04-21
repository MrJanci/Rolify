import SwiftUI

/// Kleiner runder Avatar-Button oben links in Home/Search/Library.
/// Tippt -> ProfileSheet. Zeigt Initialen oder Avatar-Image.
struct AvatarButton: View {
    let onTap: () -> Void
    @State private var api = API.shared
    @State private var user: UserProfile?

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        } label: {
            ZStack {
                Circle().fill(LinearGradient(
                    colors: [DS.accentBright, DS.accent, DS.accentDeep],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 32, height: 32)

                if let u = user {
                    Text(initials(from: u.displayName))
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .buttonStyle(.plain)
        .task {
            if user == nil {
                user = try? await api.me()
            }
        }
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}
