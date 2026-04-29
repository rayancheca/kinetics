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
            "No back camera is available on this device."
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

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                self?.configureSessionIfNeeded()
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

    nonisolated private func configureSessionIfNeeded() {
        guard !isConfigured else { return }

        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
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
