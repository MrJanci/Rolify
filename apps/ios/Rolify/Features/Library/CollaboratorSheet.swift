import SwiftUI

/// Sheet zum Verwalten der Collaborators einer Playlist.
/// Nur Owner sieht das.
struct CollaboratorSheet: View {
    let playlistId: String
    @Binding var collaborators: [CollaboratorInfo]
    @Environment(\.dismiss) var dismiss

    @State private var email = ""
    @State private var isAdding = false
    @State private var error: String?
    @State private var api = API.shared

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            VStack(spacing: DS.l) {
                header

                VStack(alignment: .leading, spacing: DS.s) {
                    Text("Email einladen")
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.textSecondary)
                    HStack {
                        TextField("freund@beispiel.de", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .font(.system(size: 15))
                            .foregroundStyle(DS.textPrimary)
                            .padding(.horizontal, DS.l)
                            .frame(height: 46)
                            .background(DS.bgElevated)
                            .clipShape(RoundedRectangle(cornerRadius: DS.radiusM))
                        Button("Laden") { Task { await addCollab() } }
                            .foregroundStyle(email.contains("@") ? DS.accent : DS.textTertiary)
                            .disabled(!email.contains("@") || isAdding)
                    }
                    if let error {
                        Text(error).font(DS.Font.footnote).foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, DS.xl)

                VStack(alignment: .leading, spacing: DS.s) {
                    Text("Dabei (\(collaborators.count))")
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.textSecondary)
                        .padding(.horizontal, DS.xl)

                    if collaborators.isEmpty {
                        Text("Noch niemand eingeladen.")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.textTertiary)
                            .padding(.horizontal, DS.xl)
                    } else {
                        ForEach(collaborators) { c in collabRow(c) }
                    }
                }

                Spacer()
            }
            .padding(.top, DS.l)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            Button("Schliessen") { dismiss() }
                .foregroundStyle(DS.textSecondary)
            Spacer()
            Text("Mitwirkende")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DS.textPrimary)
            Spacer()
            Color.clear.frame(width: 80)
        }
        .padding(.horizontal, DS.l)
    }

    private func collabRow(_ c: CollaboratorInfo) -> some View {
        HStack(spacing: DS.m) {
            ZStack {
                Circle().fill(LinearGradient(
                    colors: [DS.accentBright, DS.accentDeep],
                    startPoint: .top, endPoint: .bottom))
                    .frame(width: 40, height: 40)
                Text(initials(c.displayName))
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(c.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.textPrimary)
                Text(c.role)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DS.textSecondary)
            }
            Spacer()
            Button {
                Task { await removeCollab(c.id) }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.xl)
        .padding(.vertical, DS.s)
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    private func addCollab() async {
        isAdding = true; error = nil
        defer { isAdding = false }
        do {
            let c = try await api.addCollaborator(playlistId: playlistId, email: email.trimmingCharacters(in: .whitespacesAndNewlines))
            collaborators.append(c)
            email = ""
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            self.error = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func removeCollab(_ userId: String) async {
        do {
            try await api.removeCollaborator(playlistId: playlistId, userId: userId)
            collaborators.removeAll { $0.id == userId }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
