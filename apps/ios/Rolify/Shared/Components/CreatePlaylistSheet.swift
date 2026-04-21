import SwiftUI

/// Minimales Sheet zum Erstellen einer neuen Playlist.
/// Wird getriggert von LibraryView (Plus-Button) oder AddToPlaylistSheet (Neue Playlist).
struct CreatePlaylistSheet: View {
    let onCreated: (PlaylistSummary) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var isPublic = false
    @State private var isSubmitting = false
    @State private var error: String?
    @State private var api = API.shared
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            VStack(spacing: DS.l) {
                header

                VStack(alignment: .leading, spacing: DS.s) {
                    Text("Name")
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.textSecondary)
                    TextField("Meine neue Playlist", text: $name)
                        .focused($nameFocused)
                        .font(.system(size: 17))
                        .foregroundStyle(DS.textPrimary)
                        .padding(.horizontal, DS.l)
                        .frame(height: 48)
                        .background(DS.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: DS.radiusM, style: .continuous))
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { Task { await submit() } }
                }
                .padding(.horizontal, DS.xl)

                Toggle(isOn: $isPublic) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Oeffentlich")
                            .font(DS.Font.bodyLarge)
                            .foregroundStyle(DS.textPrimary)
                        Text("Andere Leute koennen diese Playlist finden")
                            .font(DS.Font.footnote)
                            .foregroundStyle(DS.textSecondary)
                    }
                }
                .tint(DS.accent)
                .padding(.horizontal, DS.xl)

                if let error {
                    Text(error)
                        .font(DS.Font.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, DS.xl)
                }

                Spacer()
            }
            .padding(.top, DS.l)
        }
        .preferredColorScheme(.dark)
        .onAppear { nameFocused = true }
    }

    private var header: some View {
        HStack {
            Button("Abbrechen") { dismiss() }
                .foregroundStyle(DS.textSecondary)
            Spacer()
            Text("Neue Playlist")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DS.textPrimary)
            Spacer()
            Button("Erstellen") { Task { await submit() } }
                .foregroundStyle(canSubmit ? DS.accent : DS.textTertiary)
                .disabled(!canSubmit || isSubmitting)
        }
        .padding(.horizontal, DS.l)
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() async {
        guard canSubmit, !isSubmitting else { return }
        isSubmitting = true; error = nil
        defer { isSubmitting = false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let created = try await api.createPlaylist(name: trimmed, description: nil, isPublic: isPublic)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onCreated(created)
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            self.error = error.localizedDescription
        }
    }
}
