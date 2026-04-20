import SwiftUI

/// Hero-Header mit Cover + Dominant-Color-Gradient, wie Spotify Album/Artist-Pages.
/// Fallback-Gradient wenn Image noch nicht geladen.
struct GradientHeader<Actions: View>: View {
    let title: String
    let subtitle: String?
    let coverUrl: String?
    let baseColor: Color
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [baseColor.opacity(0.9), baseColor.opacity(0.3), DS.bg],
                startPoint: .top, endPoint: .bottom
            )

            VStack(spacing: DS.m) {
                Spacer().frame(height: 24)

                CoverImage(url: coverUrl, cornerRadius: DS.radiusM)
                    .frame(width: 220, height: 220)
                    .shadow(color: .black.opacity(0.5), radius: 24, y: 12)

                Text(title)
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(DS.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, DS.xxl)
                    .padding(.top, DS.m)

                if let subtitle {
                    Text(subtitle)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.textSecondary)
                }

                actions()
                    .padding(.top, DS.s)

                Spacer().frame(height: DS.xl)
            }
        }
    }
}
