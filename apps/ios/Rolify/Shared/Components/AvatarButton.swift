import SwiftUI

/// Runder Avatar-Button oben links auf Home/Library Screens.
/// Tap oeffnet ProfileSheet (slide-in von links).
struct AvatarButton: View {
    let avatarUrl: String?
    let displayName: String
    let onTap: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        } label: {
            ZStack {
                Circle()
                    .fill(DS.bgElevated)
                    .frame(width: 32, height: 32)

                if let url = avatarUrl, !url.isEmpty {
                    AsyncImage(url: URL(string: url)) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        initialView
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                } else {
                    initialView
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var initialView: some View {
        Text(String(displayName.prefix(1)).uppercased())
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(LinearGradient(
                colors: [DS.accent, DS.accentDeep],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .clipShape(Circle())
    }
}
