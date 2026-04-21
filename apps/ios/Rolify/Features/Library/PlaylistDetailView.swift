import SwiftUI

struct PlaylistDetailView: View {
    let playlistId: String
    let initialName: String?

    @State private var detail: PlaylistDetail?
    @State private var isLoading = true
    @State private var error: String?
    @State private var api = API.shared
    @State private var player = Player.shared
    @State private var editMode: EditMode = .inactive
    @State private var showCollabSheet = false
    @State private var collaborators: [CollaboratorInfo] = []

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            if let detail {
                content(detail)
            } else if isLoading {
                ProgressView().tint(DS.accent).frame(maxHeight: .infinity)
            } else if let error {
                ErrorView(message: error) { Task { await load() } }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let d = detail, d.canEdit ?? false {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation { editMode = editMode == .active ? .inactive : .active }
                    } label: {
                        Text(editMode == .active ? "Fertig" : "Bearbeiten")
                            .foregroundStyle(DS.accent)
                    }
                }
            }
        }
        .environment(\.editMode, $editMode)
        .sheet(isPresented: $showCollabSheet) {
            CollaboratorSheet(playlistId: playlistId, collaborators: $collaborators)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ d: PlaylistDetail) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero
                VStack(spacing: DS.m) {
                    CoverImage(url: d.coverUrl.isEmpty ? nil : d.coverUrl, cornerRadius: DS.radiusM, placeholder: (d.isMixed ?? false) ? "sparkles" : "music.note.list")
                        .frame(width: 220, height: 220)
                        .shadow(color: .black.opacity(0.4), radius: 18, y: 10)

                    Text(d.name)
                        .font(DS.Font.headline)
                        .foregroundStyle(DS.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.top, DS.s)

                    HStack(spacing: DS.xs) {
                        if d.isCollaborative ?? false {
                            Image(systemName: "person.2.fill").font(.system(size: 11, weight: .bold))
                                .foregroundStyle(DS.accent)
                            Text("Kollab · ").font(DS.Font.footnote).foregroundStyle(DS.accent)
                        }
                        if d.isMixed ?? false {
                            Image(systemName: "sparkles").font(.system(size: 11, weight: .bold))
                                .foregroundStyle(DS.accent)
                            Text("Mix · ").font(DS.Font.footnote).foregroundStyle(DS.accent)
                        }
                        Text("\(d.tracks.count) Tracks")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.textTertiary)
                    }

                    if let desc = d.description, !desc.isEmpty {
                        Text(desc)
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DS.xxl)
                    }

                    // Collaborator-Avatars (wenn Collab-Playlist)
                    if let collabs = d.collaborators, !collabs.isEmpty {
                        Button { showCollabSheet = true } label: {
                            HStack(spacing: -8) {
                                ForEach(collabs.prefix(5)) { c in
                                    ZStack {
                                        Circle().fill(LinearGradient(
                                            colors: [DS.accentBright, DS.accentDeep],
                                            startPoint: .top, endPoint: .bottom))
                                            .frame(width: 26, height: 26)
                                        Text(initials(c.displayName))
                                            .font(.system(size: 10, weight: .black))
                                            .foregroundStyle(.white)
                                    }
                                    .overlay(Circle().stroke(DS.bg, lineWidth: 2))
                                }
                                if collabs.count > 5 {
                                    Text("+\(collabs.count - 5)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(DS.textSecondary)
                                        .padding(.leading, 12)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // Action-Row: Play + Collab-Verwalten (wenn Owner einer Collab-Playlist)
                    HStack(spacing: DS.m) {
                        if d.isOwned ?? false, (d.isCollaborative ?? false) {
                            Button {
                                showCollabSheet = true
                            } label: {
                                Image(systemName: "person.badge.plus")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(DS.textSecondary)
                                    .padding(12)
                                    .background(DS.bgElevated)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            guard let first = d.tracks.first else { return }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            let q = d.tracks.map { QueueTrack($0) }
                            Task { await player.play(queue: q, startingAt: first.id) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill").font(.system(size: 16, weight: .black))
                                Text("Abspielen").font(.system(size: 15, weight: .bold))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 32)
                            .frame(height: 48)
                            .background(DS.accent)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(d.tracks.isEmpty)
                    }
                    .padding(.top, DS.s)
                }
                .padding(.horizontal, DS.xl)
                .padding(.vertical, DS.xxl)

                Divider().background(DS.divider)

                LazyVStack(spacing: 0) {
                    ForEach(d.tracks) { t in
                        HStack(spacing: 0) {
                            if editMode == .active, d.canEdit ?? false {
                                Button {
                                    Task { await removeTrack(t.id) }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                        .font(.system(size: 22))
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, DS.m)
                            }
                            trackRow(t)
                        }
                    }
                    Spacer().frame(height: 120)
                }
            }
        }
    }

    private func trackRow(_ t: PlaylistTrackItem) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            let q = (detail?.tracks ?? []).map { QueueTrack($0) }
            Task { await player.play(queue: q, startingAt: t.id) }
        } label: {
            HStack(spacing: DS.m) {
                CoverImage(url: t.coverUrl, cornerRadius: DS.radiusS)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(t.title)
                        .font(DS.Font.body)
                        .foregroundStyle(player.currentTrack?.trackId == t.id ? DS.accent : DS.textPrimary)
                        .lineLimit(1)
                    Text(t.artist)
                        .font(DS.Font.footnote)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(formatDuration(ms: t.durationMs))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(DS.textSecondary)
            }
            .padding(.horizontal, DS.xl)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    private func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let d = try await api.playlistDetail(id: playlistId)
            self.detail = d
            self.collaborators = d.collaborators ?? []
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func removeTrack(_ trackId: String) async {
        do {
            try await api.removeTrackFromPlaylist(playlistId, trackId: trackId)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
