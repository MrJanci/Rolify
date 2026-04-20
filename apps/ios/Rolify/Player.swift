import Foundation
import CryptoKit
import AVFoundation
import MediaPlayer

/// Player laedt die verschluesselte Datei runter, entschluesselt lokal (AES-256-GCM)
/// und spielt ueber AVPlayer ab. Fuer MVP komplett-Download vorm Play (kein streaming-decrypt).
///
/// File-Format: [12-byte IV][ciphertext][16-byte GCM-tag] — Layout vom encryptor.py Stage.
@Observable
@MainActor
final class Player {
    static let shared = Player()

    var currentTrack: StreamManifest?
    var isPlaying: Bool = false
    var errorMessage: String?
    var progressSeconds: Double = 0
    var durationSeconds: Double = 0

    private var avPlayer: AVPlayer?
    private var timeObserver: Any?

    func play(trackId: String) async {
        errorMessage = nil
        do {
            // 1) Manifest holen (Signed-URL + masterKey)
            let manifest = try await API.shared.streamManifest(trackId: trackId)
            currentTrack = manifest

            // 2) Ciphertext runterladen
            guard let ctUrl = URL(string: manifest.signedCiphertextUrl) else {
                throw APIError.invalidURL
            }
            let (ciphertextData, _) = try await URLSession.shared.data(from: ctUrl)

            // 3) Key dekodieren
            let keyBytes = try hexToBytes(manifest.masterKeyHex)
            guard keyBytes.count == 32 else { throw APIError.decodingError("key must be 32 bytes") }
            let key = SymmetricKey(data: keyBytes)

            // 4) AES-256-GCM entschluesseln
            // Layout: [12 IV][ciphertext..][16 tag]
            guard ciphertextData.count > 28 else {
                throw APIError.decodingError("ciphertext too short")
            }
            let iv = ciphertextData.prefix(12)
            let ciphertextAndTag = ciphertextData.suffix(from: 12)
            let ciphertextBody = ciphertextAndTag.prefix(ciphertextAndTag.count - 16)
            let tag = ciphertextAndTag.suffix(16)

            let sealed = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv),
                                                ciphertext: ciphertextBody,
                                                tag: tag)
            let plaintext = try AES.GCM.open(sealed, using: key)

            // 5) Zu Temp-File schreiben und in AVPlayer laden
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("rolify-\(trackId).m4a")
            try plaintext.write(to: tempURL, options: .atomic)

            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            let item = AVPlayerItem(url: tempURL)
            let player = AVPlayer(playerItem: item)
            self.avPlayer = player

            setupTimeObserver()
            setupNowPlayingInfo(manifest: manifest)

            player.play()
            isPlaying = true
        } catch {
            errorMessage = "Playback-Fehler: \(error.localizedDescription)"
            print("Player error: \(error)")
            isPlaying = false
        }
    }

    func togglePlayPause() {
        guard let p = avPlayer else { return }
        if isPlaying {
            p.pause()
            isPlaying = false
        } else {
            p.play()
            isPlaying = true
        }
    }

    func stop() {
        avPlayer?.pause()
        avPlayer = nil
        isPlaying = false
        currentTrack = nil
        progressSeconds = 0
        if let obs = timeObserver {
            avPlayer?.removeTimeObserver(obs)
            timeObserver = nil
        }
    }

    private func setupTimeObserver() {
        guard let player = avPlayer else { return }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            Task { @MainActor in
                guard let self else { return }
                self.progressSeconds = CMTimeGetSeconds(t)
                if let d = player.currentItem?.duration, d.isValid && !d.isIndefinite {
                    self.durationSeconds = CMTimeGetSeconds(d)
                }
            }
        }
    }

    private func setupNowPlayingInfo(manifest: StreamManifest) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: manifest.title,
            MPMediaItemPropertyArtist: manifest.artist,
            MPMediaItemPropertyAlbumTitle: manifest.album,
            MPMediaItemPropertyPlaybackDuration: Double(manifest.durationMs) / 1000.0,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

private func hexToBytes(_ hex: String) throws -> Data {
    var data = Data(capacity: hex.count / 2)
    var idx = hex.startIndex
    while idx < hex.endIndex {
        let next = hex.index(idx, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
        let byteStr = hex[idx..<next]
        guard let b = UInt8(byteStr, radix: 16) else {
            throw APIError.decodingError("invalid hex in key")
        }
        data.append(b)
        idx = next
    }
    return data
}
