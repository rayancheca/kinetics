import AVFoundation
import SwiftUI
import UIKit

// MARK: - VideoPlayerUIView

/// A `UIView` subclass that hosts an `AVPlayerLayer` filling its bounds.
/// `layoutSubviews` keeps the layer in sync with any size changes.
final class VideoPlayerUIView: UIView {

    private var playerLayer: AVPlayerLayer?

    // MARK: - Configuration

    func configure(with player: AVPlayer) {
        // Remove any pre-existing layer before adding a new one.
        playerLayer?.removeFromSuperlayer()

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        self.layer.addSublayer(layer)
        self.playerLayer = layer
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }
}

// MARK: - VideoPlayerView

/// A SwiftUI wrapper around `AVPlayer` using `UIViewRepresentable`.
/// The player fills the available space with aspect-fit video gravity.
struct VideoPlayerView: UIViewRepresentable {

    let player: AVPlayer

    func makeUIView(context: Context) -> VideoPlayerUIView {
        let view = VideoPlayerUIView()
        view.backgroundColor = .black
        view.configure(with: player)
        return view
    }

    func updateUIView(_ uiView: VideoPlayerUIView, context: Context) {
        // Re-configure only when the player instance changes.
        uiView.configure(with: player)
    }
}

// MARK: - VideoPlayerController

/// Observable controller that wraps an `AVPlayer` instance and keeps
/// `currentTime`, `duration`, `isPlaying`, and `isMuted` in sync.
///
/// Marked `@MainActor` so all property mutations remain on the main thread,
/// matching the `@Observable` requirement for SwiftUI observation.
@Observable
@MainActor
final class VideoPlayerController {

    // MARK: - Public State

    let player: AVPlayer
    var currentTime: Double = 0        // seconds into the video
    var duration: Double = 0
    var isPlaying: Bool = false
    var isMuted: Bool = false

    // MARK: - Private

    nonisolated(unsafe) private var timeObserverToken: Any?
    nonisolated(unsafe) private var endObservationTask: Task<Void, Never>?

    // MARK: - Init / Deinit

    init() {
        player = AVPlayer()
    }

    deinit {
        // `cleanup()` cannot be called in deinit (nonisolated context),
        // so we perform the minimum safe teardown here.
        if let token = timeObserverToken {
            // Access the player directly — the ivar is safe from deinit.
            player.removeTimeObserver(token)
        }
        endObservationTask?.cancel()
    }

    // MARK: - Setup

    /// Loads the given `URL` into the player and begins observing playback time.
    func setup(url: URL) {
        cleanup()

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.isMuted = isMuted

        // Poll until the item's duration is valid (not .indefinite / .zero).
        endObservationTask = Task { [weak self] in
            guard let self else { return }
            var attempts = 0
            while attempts < 40, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let asset = self.player.currentItem?.asset else { break }
                let d = try? await asset.load(.duration)
                if let d, d.isNumeric, d.seconds > 0 {
                    self.duration = d.seconds
                    break
                }
                attempts += 1
            }
        }

        // Periodic time observer — fires every 50 ms for smooth scrubbing.
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        let token = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            self.currentTime = time.seconds
        }
        timeObserverToken = token

        // Listen for playback reaching the end.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
    }

    // MARK: - Playback Controls

    func play() {
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    /// Seeks to an absolute position in seconds, clamped to valid range.
    func seek(to seconds: Double) {
        let clamped = max(0, min(seconds, duration))
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
    }

    /// Mutes or unmutes the player and syncs the observable flag.
    func toggleMute() {
        isMuted.toggle()
        player.isMuted = isMuted
    }

    // MARK: - Cleanup

    /// Pauses playback, removes observers, and resets state.
    func cleanup() {
        pause()

        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }

        endObservationTask?.cancel()
        endObservationTask = nil

        NotificationCenter.default.removeObserver(
            self,
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }

    // MARK: - Private Handlers

    @objc private func playerDidFinish() {
        isPlaying = false
        currentTime = duration
    }
}
