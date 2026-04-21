import SwiftUI

/// Spotify-Style Bottom-Sheet das beim Plus-Button in LibraryView aufploppt.
/// Zeigt 5 Kreation-Optionen: Playlist / Collab / Mixed / Blend / Jam.
/// MVP: nur Playlist aktiv, Rest disabled + "Coming soon"-Subtitle.
struct CreateSheet: View {
    let onPlaylistCreated: (PlaylistSummary) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var showCreatePlaylist = false

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, DS.l)
                    .padding(.bottom, DS.s)

                row(
                    icon: "music.note.list",
                    title: "Playlist",
                    subtitle: "Baue eine neue Playlist",
                    color: DS.accent,
                    disabled: false
                ) {
                    showCreatePlaylist = true
                }

                divider

                row(
                    icon: "person.2.fill",
                    title: "Kollaborative Playlist",
                    subtitle: "Playlist mit Freunden teilen",
                    color: Color(red: 0.30, green: 0.72, blue: 0.53),
                    disabled: true,
                    hint: "Bald"
                ) {}

                divider

                row(
                    icon: "sparkles",
                    title: "Mixed Playlist",
                    subtitle: "KI-generierte Auswahl",
                    color: Color(red: 0.80, green: 0.43, blue: 0.95),
                    disabled: true,
                    hint: "Beta"
                ) {}

                divider

                row(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Blend",
                    subtitle: "Mix deiner und ihrer Taste",
                    color: Color(red: 0.95, green: 0.45, blue: 0.30),
                    disabled: true,
                    hint: "Bald"
                ) {}

                divider

                row(
                    icon: "wifi",
                    title: "Jam",
                    subtitle: "Live zusammen hoeren",
                    color: Color(red: 0.25, green: 0.58, blue: 0.92),
                    disabled: true,
                    hint: "Bald"
                ) {}

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showCreatePlaylist) {
            CreatePlaylistSheet { created in
                onPlaylistCreated(created)
                dismiss()
            }
            .presentationDetents([.medium])
        }
    }

    private var header: some View {
        HStack {
            Text("Was moechtest du erstellen?")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(DS.textPrimary)
            Spacer()
        }
        .padding(.horizontal, DS.l)
    }

    private var divider: some View {
        Divider().background(DS.divider).padding(.leading, 76)
    }

    private func row(
        icon: String,
        title: String,
        subtitle: String,
        color: Color,
        disabled: Bool,
        hint: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard !disabled else {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: DS.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: DS.radiusS, style: .continuous).fill(color)
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.black)
                }
                .frame(width: 52, height: 52)
                .opacity(disabled ? 0.5 : 1.0)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DS.s) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(disabled ? DS.textSecondary : DS.textPrimary)
                        if let hint {
                            Text(hint.uppercased())
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(DS.textSecondary)
                                .clipShape(Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, DS.l)
            .padding(.vertical, DS.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
