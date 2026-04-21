import SwiftUI

/// Spotify-Style Bottom-Sheet das beim Plus-Button in LibraryView aufploppt.
struct CreateSheet: View {
    let onPlaylistCreated: (PlaylistSummary) -> Void
    let onMixedCreated: (PlaylistSummary) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var showCreatePlaylist = false
    @State private var showCreateCollab = false
    @State private var showJam = false
    @State private var isGeneratingMix = false
    @State private var mixError: String?
    @State private var api = API.shared

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header.padding(.top, DS.l).padding(.bottom, DS.s)

                row(
                    icon: "music.note.list",
                    title: "Playlist",
                    subtitle: "Baue eine neue Playlist",
                    color: DS.accent
                ) {
                    showCreatePlaylist = true
                }

                divider

                row(
                    icon: "person.2.fill",
                    title: "Kollaborative Playlist",
                    subtitle: "Mit Freunden zusammen bauen",
                    color: DS.accentBright
                ) {
                    showCreateCollab = true
                }

                divider

                row(
                    icon: "sparkles",
                    title: "Mixed Playlist",
                    subtitle: "Algorithmisch aus deinen Likes",
                    color: Color(red: 0.80, green: 0.43, blue: 0.95),
                    hint: "Beta"
                ) {
                    Task { await generateMix() }
                }

                divider

                row(
                    icon: "wifi",
                    title: "Jam",
                    subtitle: "Live mit anderen zusammen hoeren",
                    color: Color(red: 0.25, green: 0.58, blue: 0.92)
                ) {
                    showJam = true
                }

                if isGeneratingMix {
                    ProgressView().tint(DS.accent)
                        .padding(.top, DS.m).padding(.horizontal, DS.l)
                }

                if let mixError {
                    Text(mixError)
                        .font(DS.Font.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, DS.l)
                        .padding(.top, DS.s)
                }

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
        .sheet(isPresented: $showCreateCollab) {
            CreatePlaylistSheet(startAsCollab: true) { created in
                onPlaylistCreated(created)
                dismiss()
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showJam) {
            JamSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
        hint: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
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

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DS.s) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DS.textPrimary)
                        if let hint {
                            Text(hint.uppercased())
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(DS.accent)
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

    private func generateMix() async {
        isGeneratingMix = true; mixError = nil
        defer { isGeneratingMix = false }
        do {
            let created = try await api.generateMixedPlaylist()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onMixedCreated(created)
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            self.mixError = error.localizedDescription
        }
    }
}
