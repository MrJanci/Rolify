import SwiftUI

/// Zentrale Design-Tokens fuer Rolify.
/// Farben sind aus dem Spotify-Scraping abgeleitet, aber eigene Variante
/// (Rolify-Accent ist exakt #1ED760, leicht heller als Spotify-Green #1DB954).
enum DS {
    // MARK: Colors

    static let bg = Color(red: 0.071, green: 0.071, blue: 0.071)           // #121212
    static let bgElevated = Color(red: 0.118, green: 0.118, blue: 0.118)   // #1E1E1E
    static let bgRow = Color(red: 0.094, green: 0.094, blue: 0.094)
    static let accent = Color(red: 0.118, green: 0.843, blue: 0.376)        // #1ED760

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.38)

    static let divider = Color.white.opacity(0.06)
    static let separator = Color.white.opacity(0.10)

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
