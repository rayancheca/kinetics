@preconcurrency import AVFoundation
import Foundation
import Observation
import UIKit

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
            "No camera is available on this device."
        case .sessionConfigurationFailed(let error):
            "Camera session could not be configured: \(error.localizedDescription)"
        }
    }
}

// MARK: - CameraManager

@Observable
@MainActor
final class CameraManager: NSObject {

    // MARK: - Observable State

    private(set) var isRunning = false
    private(set) var cameraError: CameraError?
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?
    private(set) var permissionDenied: Bool = false
    /// The active camera position — changes after `switchCamera()` completes.
    private(set) var cameraPosition: AVCaptureDevice.Position = .back

    // MARK: - Frame Stream

    let frameStream: AsyncStream<CMSampleBuffer>
    nonisolated(unsafe) private var frameContinuation: AsyncStream<CMSampleBuffer>.Continuation?

    // MARK: - Private

    nonisolated(unsafe) private let session = AVCaptureSession()
    nonisolated(unsafe) private var isConfigured = false
    private let sessionQueue = DispatchQueue(label: "com.kinetics.camera.session", qos: .userInteractive)

    // MARK: - Init

    override init() {
        var continuation: AsyncStream<CMSampleBuffer>.Continuation!
        frameStream = AsyncStream(CMSampleBuffer.self, bufferingPolicy: .bufferingNewest(1)) { continuation = $0 }
        frameContinuation = continuation
        super.init()
    }

    // MARK: - Public API

    func startSession() async {
        guard await checkPermissions() else {
            cameraError = .permissionDenied
            permissionDenied = true
            return
        }

        // Snapshot on main thread before crossing to sessionQueue.
        let position = cameraPosition

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                self?.configureSessionIfNeeded(position: position)
                self?.startRunningSession()
                continuation.resume()
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            Task { @MainActor [weak self] in self?.isRunning = false }
        }
    }

    /// Tears down the current capture session, flips `cameraPosition`, and rebuilds.
    /// Safe to call while a session is active — the session is stopped first.
    func switchCamera() async {
        let newPosition: AVCaptureDevice.Position = (cameraPosition == .back) ? .front : .back
        cameraPosition = newPosition

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else { continuation.resume(); return }

                // ── Stop existing session ──────────────────────────────────────
                if self.session.isRunning {
                    self.session.stopRunning()
                }
                Task { @MainActor [weak self] in self?.isRunning = false }

                // ── Remove all existing inputs and outputs ─────────────────────
                self.session.beginConfiguration()
                for input in self.session.inputs { self.session.removeInput(input) }
                for output in self.session.outputs { self.session.removeOutput(output) }
                self.session.commitConfiguration()

                // ── Reset so configureSessionIfNeeded rebuilds from scratch ────
                self.isConfigured = false
                Task { @MainActor [weak self] in self?.previewLayer = nil }

                // ── Rebuild with the new position ──────────────────────────────
                self.configureSessionIfNeeded(position: newPosition)
                self.startRunningSession()
                continuation.resume()
            }
        }
    }

    func checkPermissions() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Private — Session Configuration

    nonisolated private func configureSessionIfNeeded(position: AVCaptureDevice.Position = .back) {
        guard !isConfigured else { return }

        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
            let input = try? AVCaptureDeviceInput(device: device)
        else {
            session.commitConfiguration()
            Task { @MainActor [weak self] in self?.cameraError = .deviceNotAvailable }
            return
        }

        guard session.canAddInput(input) else { session.commitConfiguration(); return }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: sessionQueue)

        guard session.canAddOutput(output) else { session.commitConfiguration(); return }
        session.addOutput(output)

        if let connection = output.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }

        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill

        // Mirror the preview when using the front camera so the user sees themselves
        // as in a mirror — consistent with Apple's native camera behaviour.
        if let connection = layer.connection {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = (position == .front)
        }

        Task { @MainActor [weak self] in self?.previewLayer = layer }

        isConfigured = true
    }

    nonisolated private func startRunningSession() {
        guard !session.isRunning else { return }
        session.startRunning()
        Task { @MainActor [weak self] in self?.isRunning = true }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // @preconcurrency import AVFoundation suppresses the Sendable requirement
        // on CMSampleBuffer, which lacks a Sendable conformance on iOS in this SDK.
        // Thread safety is guaranteed by sessionQueue (serial) for all writes.
        frameContinuation?.yield(sampleBuffer)
    }
}
