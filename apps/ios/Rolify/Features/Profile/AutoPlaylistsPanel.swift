import SwiftUI

/// Inline-Panel fuer ProfileSheet — listet alle dynamischen Auto-Playlists
/// + per-Source enable/disable + rotation-mode toggle.
struct AutoPlaylistsPanel: View {
    @State private var sources: [API.DynamicSource] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var api = API.shared
    @State private var togglingIds: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            if isLoading && sources.isEmpty {
                HStack { Spacer(); ProgressView().tint(DS.accent); Spacer() }
                    .padding(.vertical, DS.l)
            } else if let error {
                Text(error).font(DS.Font.footnote).foregroundStyle(.red).padding(.horizontal, DS.l)
            } else if sources.isEmpty {
                Text("Noch keine Auto-Playlists. Werden taeglich vom Server generiert.")
                    .font(DS.Font.footnote)
                    .foregroundStyle(DS.textTertiary)
                    .padding(.horizontal, DS.l).padding(.vertical, DS.m)
            } else {
                ForEach(sources) { src in
                    sourceRow(src)
                    if src.id != sources.last?.id {
                        Divider().background(DS.divider).padding(.leading, DS.l)
                    }
                }
            }
        }
        .padding(.vertical, DS.s)
        .task { await load() }
    }

    private func sourceRow(_ src: API.DynamicSource) -> some View {
        HStack(spacing: DS.m) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.radiusS)
                    .fill(LinearGradient(
                        colors: [DS.accentBright, DS.accentDeep],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: iconFor(source: src.source))
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(src.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text("\(src.trackCount) Tracks")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.textSecondary)
                    Text("·").font(.system(size: 11)).foregroundStyle(DS.textTertiary)
                    Menu {
                        Button { Task { await updateRotation(src, to: "rotate") } } label: {
                            Label("Rotation (alte raus)", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button { Task { await updateRotation(src, to: "accumulate") } } label: {
                            Label("Akkumulieren (alte bleiben)", systemImage: "plus.square.on.square")
                        }
                    } label: {
                        Text(src.rotationMode == "rotate" ? "Rotation" : "Akkum.")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.accent)
                    }
                }
            }

            Spacer()

            if togglingIds.contains(src.source) {
                ProgressView().tint(DS.accent).scaleEffect(0.7)
            } else {
                Toggle("", isOn: Binding(
                    get: { src.enabled },
                    set: { newVal in Task { await toggle(src, to: newVal) } }
                ))
                .labelsHidden()
                .tint(DS.accent)
            }
        }
        .padding(.horizontal, DS.l).padding(.vertical, DS.s)
    }

    private func iconFor(source: String) -> String {
        if source.contains("tiktok") { return "music.note.tv" }
        if source.contains("rap") { return "headphones" }
        if source.contains("pop") { return "music.mic" }
        if source.contains("de:") { return "flag" }
        return "globe"
    }

    private func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do { self.sources = try await api.dynamicSources() }
        catch { self.error = error.localizedDescription }
    }

    private func toggle(_ src: API.DynamicSource, to enabled: Bool) async {
        togglingIds.insert(src.source)
        defer { togglingIds.remove(src.source) }
        do {
            try await api.toggleDynamicSource(source: src.source, enabled: enabled)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // Optimistic update statt full reload
            if let idx = sources.firstIndex(where: { $0.source == src.source }) {
                sources[idx] = API.DynamicSource(
                    id: src.id, name: src.name, description: src.description,
                    coverUrl: src.coverUrl, source: src.source,
                    rotationMode: src.rotationMode, refreshIntervalH: src.refreshIntervalH,
                    lastRefreshedAt: src.lastRefreshedAt, trackCount: src.trackCount,
                    enabled: enabled
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func updateRotation(_ src: API.DynamicSource, to mode: String) async {
        do {
            try await api.updateDynamicSource(source: src.source, rotationMode: mode)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
