import Foundation
import CryptoKit
import AVFoundation
import MediaPlayer
import UIKit

/// Player laedt die verschluesselte Datei runter, entschluesselt lokal (AES-256-GCM)
/// und spielt ueber AVPlayer ab. Fuer MVP komplett-Download vorm Play (kein streaming-decrypt).
///
/// File-Format: [12-byte IV][ciphertext][16-byte GCM-tag] - Layout vom encryptor.py Stage.
///
/// Integrations:
/// - MPNowPlayingInfoCenter (Lockscreen + Control Center + Bluetooth-Autoradio-Display)
/// - MPRemoteCommandCenter (Lockscreen Play/Pause/Skip + Remote-Commands vom Bluetooth-Device)
/// - AVAudioSession .playback (Background-Audio, Siehe Info.plist UIBackgroundModes)
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
    private var endObserver: NSObjectProtocol?
    private var remoteCommandsSetup = false

    init() {
        setupRemoteCommands()
    }

    // MARK: Queue-Helpers

    /// Startet Playback einer kompletten Queue. Wiring fuer onAdvance/onRewind
    /// setzt Player auf Queue.advance/rewind (Lockscreen + End-of-Track).
    func play(queue tracks: [QueueTrack], startingAt trackId: String) async {
        PlaybackQueue.shared.setQueue(tracks, startingAt: trackId)
        await play(trackId: trackId)
    }

    /// Wird beim End-of-Track vom AVPlayerItemDidPlayToEndTime-Observer aufgerufen.
    private func advanceQueue() async {
        if let next = PlaybackQueue.shared.advance() {
            await play(trackId: next.id)
        } else {
            stop()
        }
    }

    private func rewindQueue() async {
        if let prev = PlaybackQueue.shared.rewind() {
            await play(trackId: prev.id)
        }
    }

    // MARK: Public API

    func play(trackId: String) async {
        // Alten Player sauber abreissen (sonst spielen 2 Tracks parallel)
        teardownCurrent()
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

            // 4) AES-256-GCM entschluesseln — Layout: [12 IV][ciphertext..][16 tag]
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

            // 5) Temp-File schreiben + AVPlayer laden
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("rolify-\(trackId).m4a")
            try plaintext.write(to: tempURL, options: .atomic)

            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
            try AVAudioSession.sharedInstance().setActive(true)

            let item = AVPlayerItem(url: tempURL)
            let player = AVPlayer(playerItem: item)
            player.automaticallyWaitsToMinimizeStalling = false
            self.avPlayer = player

            setupTimeObserver()
            setupEndObserver(for: item)
            await setupNowPlayingInfo(manifest: manifest)

            player.play()
            isPlaying = true
            updatePlaybackRateInfo(rate: 1.0)

            // Jam-Broadcast: Host-einer-Session broadcastet track_change
            // Unterstuetzt beide Transports (WG + BT)
            let jam = JamOrchestrator.shared
            if jam.isConnected {
                switch jam.mode {
                case .wireguard where jam.client.isHost:
                    await jam.client.sendTrackChange(trackId: trackId, positionMs: 0)
                case .bluetooth where jam.isBluetoothHost:
                    await jam.btSendTrackChange(trackId: trackId, positionMs: 0)
                default: break
                }
            }
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
            updatePlaybackRateInfo(rate: 0.0)
            broadcastJamControl(playing: false)
        } else {
            p.play()
            isPlaying = true
            updatePlaybackRateInfo(rate: 1.0)
            broadcastJamControl(playing: true)
        }
    }

    private func broadcastJamControl(playing: Bool) {
        let jam = JamOrchestrator.shared
        guard jam.isConnected else { return }
        let posMs = Int(progressSeconds * 1000)
        Task { @MainActor in
            switch jam.mode {
            case .wireguard where jam.client.isHost:
                if playing { await jam.client.sendPlay(positionMs: posMs) }
                else { await jam.client.sendPause(positionMs: posMs) }
            case .bluetooth where jam.isBluetoothHost:
                await jam.btSendControl(playing: playing, positionMs: posMs)
            default: break
            }
        }
    }

    func seek(seconds: Double) {
        guard let p = avPlayer else { return }
        let target = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        p.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.progressSeconds = seconds
                self.updateElapsedTimeInfo()

                // Jam-Broadcast (WG + BT)
                let jam = JamOrchestrator.shared
                if jam.isConnected {
                    let posMs = Int(seconds * 1000)
                    switch jam.mode {
                    case .wireguard where jam.client.isHost:
                        await jam.client.sendSeek(positionMs: posMs)
                    case .bluetooth where jam.isBluetoothHost:
                        await jam.btSendSeek(positionMs: posMs)
                    default: break
                    }
                }
            }
        }
    }

    func stop() {
        teardownCurrent()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: Teardown

    /// Reisst aktuelle Playback-Session sauber ab. KRITISCH: removeTimeObserver MUSS vor
    /// avPlayer = nil laufen, sonst leakt der Observer und der alte AVPlayer laeuft im Background.
    private func teardownCurrent() {
        if let obs = timeObserver, let p = avPlayer {
            p.removeTimeObserver(obs)
        }
        timeObserver = nil

        if let ob = endObserver {
            NotificationCenter.default.removeObserver(ob)
        }
        endObserver = nil

        avPlayer?.pause()
        avPlayer?.replaceCurrentItem(with: nil)
        avPlayer = nil

        isPlaying = false
        currentTrack = nil
        progressSeconds = 0
        durationSeconds = 0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: Observers

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
                self.updateElapsedTimeInfo()
            }
        }
    }

    private func setupEndObserver(for item: AVPlayerItem) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.advanceQueue()
            }
        }
    }

    // MARK: NowPlayingInfo + Artwork

    private func setupNowPlayingInfo(manifest: StreamManifest) async {
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: manifest.title,
            MPMediaItemPropertyArtist: manifest.artist,
            MPMediaItemPropertyAlbumTitle: manifest.album,
            MPMediaItemPropertyPlaybackDuration: Double(manifest.durationMs) / 1000.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // Artwork async nachladen — kein Block, damit Title sofort auf Lockscreen sichtbar ist
        if let artwork = await NowPlayingArtwork.load(from: manifest.coverUrl) {
            var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            updated[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
        }
    }

    private func updateElapsedTimeInfo() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progressSeconds
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updatePlaybackRateInfo(rate: Double) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: Remote Commands (Lockscreen, Control Center, Bluetooth-Auto)

    private func setupRemoteCommands() {
        guard !remoteCommandsSetup else { return }
        remoteCommandsSetup = true

        let c = MPRemoteCommandCenter.shared()

        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.avPlayer else { return }
                if !self.isPlaying {
                    p.play()
                    self.isPlaying = true
                    self.updatePlaybackRateInfo(rate: 1.0)
                }
            }
            return .success
        }

        c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.avPlayer else { return }
                if self.isPlaying {
                    p.pause()
                    self.isPlaying = false
                    self.updatePlaybackRateInfo(rate: 0.0)
                }
            }
            return .success
        }

        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }

        c.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in await self?.advanceQueue() }
            return .success
        }

        c.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in await self?.rewindQueue() }
            return .success
        }

        c.changePlaybackPositionCommand.addTarget { [weak self] ev in
            guard let e = ev as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(seconds: e.positionTime) }
            return .success
        }

        // Skip-Seconds (±15s) deaktivieren - fuer BT-Auto das manche dafuer Next/Previous mappen
        c.skipForwardCommand.isEnabled = false
        c.skipBackwardCommand.isEnabled = false
    }
}

// MARK: - Artwork Loader

enum NowPlayingArtwork {
    private static var cache: [String: MPMediaItemArtwork] = [:]

    static func load(from urlString: String) async -> MPMediaItemArtwork? {
        if let cached = cache[urlString] { return cached }
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            cache[urlString] = artwork
            return artwork
        } catch {
            return nil
        }
    }
}

// MARK: - Helpers

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
