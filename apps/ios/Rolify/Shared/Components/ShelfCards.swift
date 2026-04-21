import SwiftUI

/// Grosse Mixes-Card (Top-Mixes-Shelf auf Home).
/// 170x170 Cover mit Brand-Icon oben-links + Overlay-Banner unten mit Mix-Namen.
struct MixShelfCard: View {
    let title: String
    let coverUrl: String
    let subtitle: String
    let accentColor: Color
    let onTap: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: DS.s) {
                cardStack
                subtitleLabel
            }
        }
        .buttonStyle(.plain)
    }

    private var cardStack: some View {
        ZStack(alignment: .topLeading) {
            CoverImage(url: coverUrl, cornerRadius: DS.radiusS)
                .frame(width: 170, height: 170)
            brandIcon
            bottomBanner
        }
        .frame(width: 170, height: 170)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusS, style: .continuous))
    }

    private var brandIcon: some View {
        ZStack {
            Circle().fill(.black.opacity(0.7)).frame(width: 28, height: 28)
            Image(systemName: "music.note")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DS.accent)
        }
        .padding(DS.s)
    }

    private var bottomBanner: some View {
        VStack {
            Spacer()
            HStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.m)
                    .padding(.vertical, DS.s)
                Spacer(minLength: 0)
            }
            .background(accentColor)
        }
    }

    private var subtitleLabel: some View {
        Text(subtitle)
            .font(.system(size: 12))
            .foregroundStyle(DS.textSecondary)
            .lineLimit(2)
            .frame(width: 170, alignment: .leading)
    }
}

/// Square card fuer Jump-back-in Shelf.
struct JumpBackCard: View {
    let coverUrl: String?
    let title: String?
    let onTap: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: DS.xs) {
                CoverImage(url: coverUrl, cornerRadius: DS.radiusS)
                    .frame(width: 150, height: 150)

                if let title {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                        .frame(width: 150, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
