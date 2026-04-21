import SwiftUI

/// Kachel im 2-column-Grid auf Home: kleines Cover links + Titel rechts (max 2 Zeilen).
/// Spotify-Style: bgRow, rounded-4, hoehe ~56pt, Cover 56x56 flush links.
struct QuickPickTile: View {
    let title: String
    let coverUrl: String?
    let onTap: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            onTap()
        } label: {
            HStack(spacing: 0) {
                CoverImage(url: coverUrl, cornerRadius: 0)
                    .frame(width: 56, height: 56)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, DS.s)
                    .padding(.trailing, DS.s)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56, alignment: .leading)
            .background(DS.bgElevated.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusS, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
