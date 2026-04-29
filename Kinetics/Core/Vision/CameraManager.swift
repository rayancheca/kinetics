import AVFoundation
import Foundation
import Observation

// MARK: - CameraError

enum CameraError: LocalizedError, Sendable {
    case permissionDenied
    case deviceNotAvailable
    case sessionConfigurationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Camera access was denied. Please enable it in Settings > Kinetics > Camera."
        case .deviceNotAvailable:
            "No back camera is available on this device."
        case .sessionConfigurationFailed(let error):
            "Camera session could not be configured: \(error.localizedDescription)"
        }
    }
}

// MARK: - CameraManager

/// Wraps an `AVCaptureSession` and exposes camera frames as an `AsyncStream<CMSampleBuffer>`.
///
/// **Threading model:**
/// - All AVFoundation session work runs on `sessionQueue` (a dedicated serial DispatchQueue).
/// - UI-observable state (`isRunning`, `cameraError`, `previewLayer`) is always mutated on
///   `@MainActor` via `Task { @MainActor in ... }`.
/// - The delegate callback (`captureOutput`) runs on `sessionQueue`; it simply yields the
///   buffer into `frameContinuation`, which is thread-safe (`AsyncStream.Continuation` is `Sendable`).
@Observable
@MainActor
final class CameraManager: NSObject {

    // MARK: - Observable State

    private(set) var isRunning = false
    private(set) var cameraError: CameraError?
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: - Frame Stream

    /// Consume this stream from a processing actor to receive raw video frames.
    /// Buffering policy discards all but the newest frame to prevent memory build-up.
    let frameStream: AsyncStream<CMSampleBuffer>

    /// Thread-safe continuation bridging AVFoundation's delegate callback into the async stream.
    /// `nonisolated(unsafe)` is correct here: `AsyncStream.Continuation` is itself `Sendable`,
    /// and we only call `yield` on it from the AVFoundation delegate queue.
    nonisolated(unsafe) private var frameContinuation: AsyncStream<CMSampleBuffer>.Continuation?

    // MARK: - Private

    nonisolated(unsafe) private let session = AVCaptureSession()

    /// Dedicated serial queue for all AVCaptureSession configuration and start/stop operations.
    private let sessionQueue = DispatchQueue(
        label: "com.kinetics.camera.session",
        qos: .userInteractive
    )

    // MARK: - Init

    override init() {
        // Wire up the AsyncStream before super.init so the stored property is set atomically.
        var continuation: AsyncStream<CMSampleBuffer>.Continuation!
        frameStream = AsyncStream(
            CMSampleBuffer.self,
            bufferingPolicy: .bufferingNewest(1)
        ) { continuation = $0 }
        frameContinuation = continuation
        super.init()
    }

    // MARK: - Public API

    /// Requests camera permission (if needed), configures the session, and starts capture.
    /// Safe to call multiple times — no-ops if the session is already running.
    func startSession() async {
        guard await checkPermissions() else {
            cameraError = .permissionDenied
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                self?.configureAndStartSession()
                continuation.resume()
            }
        }
    }

    /// Stops the capture session. Safe to call even when the session is not running.
    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            Task { @MainActor [weak self] in
                self?.isRunning = false
            }
        }
    }

    /// Returns `true` if video capture access is currently authorized.
    /// Presents the system permission prompt when status is `.notDetermined`.
    func checkPermissions() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    // MARK: - Private — Session Configuration

    /// Must be called on `sessionQueue`.
    nonisolated private func configureAndStartSession() {
        guard !session.isRunning else { return }

        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        // MARK: Input
        guard
            let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .back
            ),
            let input = try? AVCaptureDeviceInput(device: device)
        else {
            session.commitConfiguration()
            Task { @MainActor [weak self] in
                self?.cameraError = .deviceNotAvailable
            }
            return
        }

        guard session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        // MARK: Output
        let output = AVCaptureVideoDataOutput()
        // BGRA is what Vision's pixel-buffer path expects.
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        // Drop frames we cannot process in time rather than backing up memory.
        output.alwaysDiscardsLateVideoFrames = true
        // Delegate runs on sessionQueue (same queue as configuration for safety).
        output.setSampleBufferDelegate(self, queue: sessionQueue)

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)

        // MARK: Orientation
        // Rotate to portrait so Vision receives upright frames without extra transforms.
        if let connection = output.connection(with: .video) {
            // `videoRotationAngle` replaces the deprecated `videoOrientation` in iOS 17+.
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }

        session.commitConfiguration()
        session.startRunning()

        // Build the preview layer on the session queue (safe — it only reads the session).
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill

        Task { @MainActor [weak self] in
            self?.previewLayer = layer
            self?.isRunning = true
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    /// Called on `sessionQueue` for every new frame.
    /// We yield the buffer to the async stream continuation; `AsyncStream.Continuation.yield`
    /// is thread-safe so no additional synchronization is needed.
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameContinuation?.yield(sampleBuffer)
    }
}
