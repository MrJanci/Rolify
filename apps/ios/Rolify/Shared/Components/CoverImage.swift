import SwiftUI

/// AsyncImage mit graceful loading-states + fallback icon.
/// Wird ueberall fuer Album-Covers und Artist-Images verwendet.
struct CoverImage: View {
    let url: String?
    var cornerRadius: CGFloat = DS.radiusS
    var placeholder: String = "music.note"

    var body: some View {
        Group {
            if let urlString = url, let url = URL(string: urlString) {
                AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    case .empty:
                        placeholderView(withLoader: true)
                    case .failure:
                        placeholderView(withLoader: false)
                    @unknown default:
                        placeholderView(withLoader: false)
                    }
                }
            } else {
                placeholderView(withLoader: false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func placeholderView(withLoader: Bool) -> some View {
        ZStack {
            LinearGradient(colors: [DS.bgElevated, DS.bgRow], startPoint: .topLeading, endPoint: .bottomTrailing)
            if withLoader {
                ProgressView().tint(DS.textSecondary).scaleEffect(0.6)
            } else {
                Image(systemName: placeholder)
                    .foregroundStyle(DS.textSecondary)
                    .font(.system(size: 20, weight: .medium))
            }
        }
    }
}
