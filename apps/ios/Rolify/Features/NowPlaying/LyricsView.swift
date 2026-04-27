import SwiftUI

/// Time-synced Lyrics-Display.
/// LRC-Format: "[mm:ss.xx]text\n[mm:ss.xx]text\n..."
/// Wir parsen das in [Line(timeMs, text)] und highlighten die aktive Zeile via player.progressSeconds.
struct LyricsView: View {
    let trackId: String
    let title: String
    let artist: String

    @Environment(\.dismiss) var dismiss
    @State private var api = API.shared
    @State private var player = Player.shared
    @State private var lyrics: API.LyricsResponse?
    @State private var lines: [LyricLine] = []
    @State private var isLoading = true
    @State private var error: String?

    struct LyricLine: Identifiable, Hashable {
        let id: Int
        let timeMs: Int
        let text: String
    }

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()
            content
        }
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            header
            if isLoading && lyrics == nil {
                ProgressView().tint(DS.accent).frame(maxHeight: .infinity)
            } else if let lyrics, lyrics.hasSync, !lines.isEmpty {
                syncedLyricsScroll
            } else if let lyrics, let plain = lyrics.plain, !plain.isEmpty {
                plainLyricsScroll(plain)
            } else if let _ = error ?? lyrics.map({ _ in nil }) {
                emptyState
            } else {
                emptyState
            }
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(DS.textPrimary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Lyrics").font(.system(size: 14, weight: .bold)).foregroundStyle(DS.textPrimary)
                Spacer()
                Color.clear.frame(width: 36, height: 36)
            }
            Text("\(title) · \(artist)")
                .font(DS.Font.footnote)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, DS.l)
        .padding(.top, DS.l)
        .padding(.bottom, DS.s)
    }

    @ViewBuilder
    private var syncedLyricsScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.m) {
                    Spacer().frame(height: 60)
                    let activeId = activeLineId
                    ForEach(lines) { line in
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.system(size: line.id == activeId ? 22 : 18,
                                           weight: line.id == activeId ? .black : .semibold))
                            .foregroundStyle(line.id == activeId ? DS.accent : DS.textSecondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DS.xl)
                            .id(line.id)
                            .animation(.easeInOut(duration: 0.2), value: activeId)
                    }
                    Spacer().frame(height: 200)
                }
            }
            .onChange(of: activeLineId) { _, newId in
                if let newId {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newId, anchor: .center)
                    }
                }
            }
        }
    }

    private func plainLyricsScroll(_ plain: String) -> some View {
        ScrollView {
            Text(plain)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.xl)
                .padding(.vertical, DS.l)
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.m) {
            Spacer()
            Image(systemName: "text.bubble")
                .font(.system(size: 44))
                .foregroundStyle(DS.textSecondary)
            Text("Keine Lyrics gefunden")
                .font(DS.Font.bodyLarge)
                .foregroundStyle(DS.textPrimary)
            Text("LRClib hat fuer diesen Track noch keinen Eintrag.")
                .font(DS.Font.footnote)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.xxl)
            Spacer()
        }
    }

    private var activeLineId: Int? {
        let progressMs = Int(player.progressSeconds * 1000)
        var current: Int? = nil
        for line in lines {
            if line.timeMs <= progressMs { current = line.id }
            else { break }
        }
        return current
    }

    private func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let r = try await api.fetchLyrics(trackId: trackId)
            self.lyrics = r
            if let lrc = r.lrcSynced {
                self.lines = parseLrc(lrc)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Parses LRC-Format "[mm:ss.xx]text" Zeilen → [LyricLine].
    private func parseLrc(_ lrc: String) -> [LyricLine] {
        var result: [LyricLine] = []
        var idCounter = 0
        // Multi-timestamp pro Zeile moeglich: "[00:14.20][00:30.10]Hey"
        let timePattern = try? NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?\]"#)
        for raw in lrc.split(separator: "\n") {
            let line = String(raw)
            guard let regex = timePattern else { continue }
            let nsLine = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            if matches.isEmpty { continue }
            // Text nach letztem timestamp
            let lastMatch = matches.last!
            let textStart = lastMatch.range.location + lastMatch.range.length
            let text = textStart < nsLine.length
                ? nsLine.substring(from: textStart).trimmingCharacters(in: .whitespaces)
                : ""
            for m in matches {
                let mm = Int(nsLine.substring(with: m.range(at: 1))) ?? 0
                let ss = Int(nsLine.substring(with: m.range(at: 2))) ?? 0
                let cs: Int = {
                    let r = m.range(at: 3)
                    if r.location == NSNotFound { return 0 }
                    let raw = nsLine.substring(with: r)
                    let val = Int(raw) ?? 0
                    return raw.count == 2 ? val * 10 : val   // "20" → 200ms, "200" → 200ms
                }()
                let timeMs = (mm * 60 + ss) * 1000 + cs
                result.append(LyricLine(id: idCounter, timeMs: timeMs, text: text))
                idCounter += 1
            }
        }
        return result.sorted(by: { $0.timeMs < $1.timeMs })
    }
}
