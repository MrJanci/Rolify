import SwiftUI

/// Horizontal scrollende Filter-Pills (wie Spotify: All/Music/Podcasts oder Playlists/Albums/Artists/Downloaded).
/// Selected pill nutzt accent background, unselected hat dunkles bgElevated.
struct TopBarPills: View {
    let options: [String]
    @Binding var selection: String
    var allowDeselect: Bool = true   // Library-Style: kann zu nil zurueckschalten via re-tap

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.s) {
                ForEach(options, id: \.self) { option in
                    pill(option)
                }
            }
            .padding(.horizontal, DS.l)
        }
    }

    private func pill(_ option: String) -> some View {
        let isSelected = selection == option
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if isSelected && allowDeselect {
                selection = ""
            } else {
                selection = option
            }
        } label: {
            Text(option)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? .black : DS.textPrimary)
                .padding(.horizontal, DS.l)
                .padding(.vertical, DS.s)
                .background(isSelected ? DS.accent : Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
