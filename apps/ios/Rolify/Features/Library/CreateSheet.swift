import SwiftUI

/// Spotify-style "+" Bottom-Sheet (5 Optionen).
struct CreateSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var showCreatePlaylist: Bool

    var body: some View {
        ZStack {
            DS.bgElevated.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: DS.xl)

                option(icon: "music.note", title: "Playlist",
                       subtitle: "Mit Tracks oder Episoden erstellen") {
                    dismiss()
                    // kleine Verzoegerung fuer clean-transition zwischen sheets
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        showCreatePlaylist = true
                    }
                }

                option(icon: "person.2.fill", title: "Gemeinsame Playlist",
                       subtitle: "Mit Freunden zusammen erstellen",
                       disabled: true)

                option(icon: "slider.horizontal.3", title: "Mixed Playlist",
                       subtitle: "Tracks mit fliessenden Uebergaengen",
                       badge: "Beta",
                       disabled: true)

                option(icon: "circle.grid.2x1.fill", title: "Blend",
                       subtitle: "Geschmaecker deiner Freunde mixen",
                       disabled: true)

                option(icon: "person.line.dotted.person.fill", title: "Jam",
                       subtitle: "Gemeinsam hoeren von ueberall",
                       disabled: true)

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func option(icon: String, title: String, subtitle: String,
                        badge: String? = nil, disabled: Bool = false,
                        action: (() -> Void)? = nil) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action?()
        } label: {
            HStack(spacing: DS.l) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.10))
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(disabled ? DS.textTertiary : DS.textPrimary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: DS.s) {
                        Text(title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(disabled ? DS.textSecondary : DS.textPrimary)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, DS.xs + 2)
                                .padding(.vertical, 2)
                                .background(DS.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(DS.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, DS.xl)
            .padding(.vertical, DS.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
