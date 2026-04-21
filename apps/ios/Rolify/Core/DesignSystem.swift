import SwiftUI

/// Zentrale Design-Tokens fuer Rolify.
/// Palette vom R:\landingPage\RolakInvoice Website uebernommen (Primary: Blue-500 #3B82F6).
/// Adaptiert fuer Dark-Mode mit leicht blauem Tint in den Backgrounds.
enum DS {
    // MARK: Colors

    static let bg = Color.black                                            // #000000 - Spotify pure black
    static let bgElevated = Color(red: 0.12, green: 0.12, blue: 0.12)      // #1F1F1F - elevated card (Spotify-style)
    static let bgRow = Color(red: 0.08, green: 0.08, blue: 0.08)           // #141414 - row bg

    static let accent = Color(red: 0.231, green: 0.510, blue: 0.965)       // #3B82F6 - Blue-500 (primary, from landing page)
    static let accentBright = Color(red: 0.376, green: 0.647, blue: 0.980) // #60A5FA - Blue-400 (hover/active)
    static let accentDeep = Color(red: 0.114, green: 0.306, blue: 0.847)   // #1D4ED8 - Blue-700 (pressed)

    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0.631, green: 0.698, blue: 0.820) // #A1B2D1 - blueish grey
    static let textTertiary = Color.white.opacity(0.38)

    static let divider = Color(red: 1, green: 1, blue: 1).opacity(0.07)
    static let separator = Color(red: 1, green: 1, blue: 1).opacity(0.12)

    // MARK: Spacing

    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32

    // MARK: Radius

    static let radiusS: CGFloat = 4
    static let radiusM: CGFloat = 8
    static let radiusL: CGFloat = 12
    static let radiusXL: CGFloat = 16

    // MARK: Typography (shortcuts — SwiftUI spec inline, aber mit konsistenten sizes)

    enum Font {
        static func display(size: CGFloat = 48) -> SwiftUI.Font { .system(size: size, weight: .black) }
        static let headline = SwiftUI.Font.system(size: 28, weight: .black)
        static let title = SwiftUI.Font.system(size: 22, weight: .bold)
        static let bodyLarge = SwiftUI.Font.system(size: 16, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 15)
        static let caption = SwiftUI.Font.system(size: 13)
        static let footnote = SwiftUI.Font.system(size: 12, weight: .medium)
    }
}

// (Rueckwaerts-Kompat-Alias `Rolify` entfernt — kann mit Module-Namen kollidieren.)

// MARK: Helpers (duration formatting)

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

// MARK: - Shared ErrorView (inline hier, weil XcodeGen separate files manchmal nicht picked)

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: DS.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.red)
            Text(message)
                .foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Nochmal", action: onRetry)
                .foregroundStyle(DS.accent)
        }
        .frame(maxHeight: .infinity)
    }
}
