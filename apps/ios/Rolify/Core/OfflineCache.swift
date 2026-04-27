import Foundation
import CryptoKit

/// FileManager-basierter Cache fuer offline-verfuegbare Tracks.
/// Encrypted .enc Files bleiben verschluesselt auf Disk (decrypt-on-play wie bei stream).
///
/// Pfad: `~/Library/Caches/rolify-offline/<trackId>.enc`
/// Index: UserDefaults dict `rolify.offline.index` = [trackId: { downloadedAt, masterKeyHex, expiresAt, sizeBytes }]
@Observable
@MainActor
final class OfflineCache {
    static let shared = OfflineCache()

    struct Entry: Codable, Hashable {
        let trackId: String
        let downloadedAt: Date
        let expiresAt: Date
        let masterKeyHex: String
        let sizeBytes: Int
    }

    private(set) var entries: [String: Entry] = [:]
    private(set) var activeDownloads: Set<String> = []
    private static let indexKey = "rolify.offline.index"
    private static let dirName = "rolify-offline"

    init() {
        loadIndex()
    }

    // MARK: Public

    /// True wenn Track lokal verfuegbar + nicht abgelaufen.
    func isAvailable(trackId: String) -> Bool {
        guard let entry = entries[trackId] else { return false }
        if entry.expiresAt < Date() {
            // Abgelaufen → cleanup
            try? FileManager.default.removeItem(at: localPath(for: trackId))
            entries.removeValue(forKey: trackId)
            saveIndex()
            return false
        }
        return FileManager.default.fileExists(atPath: localPath(for: trackId).path)
    }

    /// Returns local file URL (.enc, encrypted). Caller must decrypt on read.
    func localPath(for trackId: String) -> URL {
        cacheDir().appendingPathComponent("\(trackId).enc")
    }

    func masterKey(for trackId: String) -> Data? {
        guard let entry = entries[trackId] else { return nil }
        return Data(hexString: entry.masterKeyHex)
    }

    /// Download + persist. Throws bei Fehler. Nach Erfolg → entries updated + Notification.
    func download(trackId: String) async throws {
        if isAvailable(trackId: trackId) { return }
        if activeDownloads.contains(trackId) { return }
        activeDownloads.insert(trackId)
        defer { activeDownloads.remove(trackId) }

        let api = API.shared
        let lic = try await api.requestOfflineLicense(trackId: trackId)
        guard let url = URL(string: lic.downloadUrl) else {
            throw NSError(domain: "OfflineCache", code: 1, userInfo: [NSLocalizedDescriptionKey: "invalid url"])
        }

        // Download .enc-Bytes
        let (data, _) = try await URLSession.shared.data(from: url)

        // Persistieren
        try FileManager.default.createDirectory(at: cacheDir(), withIntermediateDirectories: true)
        let dest = localPath(for: trackId)
        try data.write(to: dest, options: .atomic)

        // ISO-8601 expiresAt parsen
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expiresAt = isoFmt.date(from: lic.expiresAt) ??
                        ISO8601DateFormatter().date(from: lic.expiresAt) ??
                        Date().addingTimeInterval(30 * 24 * 3600)

        let entry = Entry(
            trackId: trackId,
            downloadedAt: Date(),
            expiresAt: expiresAt,
            masterKeyHex: lic.masterKeyHex,
            sizeBytes: data.count,
        )
        entries[trackId] = entry
        saveIndex()
    }

    func remove(trackId: String) async {
        try? FileManager.default.removeItem(at: localPath(for: trackId))
        entries.removeValue(forKey: trackId)
        saveIndex()
        try? await API.shared.revokeOfflineLicense(trackId: trackId)
    }

    func totalSizeBytes() -> Int {
        entries.values.reduce(0) { $0 + $1.sizeBytes }
    }

    // MARK: Private

    private func cacheDir() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent(Self.dirName, isDirectory: true)
    }

    private func loadIndex() {
        guard let data = UserDefaults.standard.data(forKey: Self.indexKey),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return }
        self.entries = decoded
    }

    private func saveIndex() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.indexKey)
        }
    }
}

// Hex-Decode-Helper (Player.swift hat schon einen, aber separat fuer Cache)
private extension Data {
    init?(hexString: String) {
        let hex = hexString.replacingOccurrences(of: " ", with: "")
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            let byteStr = hex[idx..<next]
            guard let b = UInt8(byteStr, radix: 16) else { return nil }
            data.append(b)
            idx = next
        }
        self = data
    }
}
