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
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation { editMode = editMode == .active ? .inactive : .active }
                } label: {
                    Text(editMode == .active ? "Fertig" : "Bearbeiten")
                        .foregroundStyle(DS.accent)
                }
            }
        }
        .environment(\.editMode, $editMode)
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ d: PlaylistDetail) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero
                VStack(spacing: DS.m) {
                    CoverImage(url: d.coverUrl.isEmpty ? nil : d.coverUrl, cornerRadius: DS.radiusM, placeholder: "music.note.list")
                        .frame(width: 220, height: 220)
                        .shadow(color: .black.opacity(0.4), radius: 18, y: 10)

                    Text(d.name)
                        .font(DS.Font.headline)
                        .foregroundStyle(DS.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.top, DS.s)

                    if let desc = d.description, !desc.isEmpty {
                        Text(desc)
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DS.xxl)
                    }

                    Text("\(d.tracks.count) Tracks")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.textTertiary)

                    // Play Button
                    Button {
                        guard let first = d.tracks.first else { return }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task { await player.play(trackId: first.id) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16, weight: .black))
                            Text("Abspielen")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 32)
                        .frame(height: 48)
                        .background(DS.accent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, DS.m)
                    .disabled(d.tracks.isEmpty)
                }
                .padding(.horizontal, DS.xl)
                .padding(.vertical, DS.xxl)

                Divider().background(DS.divider)

                // Track list with edit mode
                LazyVStack(spacing: 0) {
                    ForEach(d.tracks) { t in
                        HStack(spacing: 0) {
                            if editMode == .active {
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
            Task { await player.play(trackId: t.id) }
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

    private func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            self.detail = try await api.playlistDetail(id: playlistId)
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
