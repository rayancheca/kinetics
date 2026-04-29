import SwiftUI
import UIKit
import AVFoundation

// MARK: - CameraPreviewView

/// A SwiftUI wrapper around `AVCaptureVideoPreviewLayer` that fills its parent
/// with the live camera feed. Uses `UIViewRepresentable` because SwiftUI has no
/// native layer-level API for AVFoundation preview layers.
///
/// Usage:
/// ```swift
/// CameraPreviewView(cameraManager: cameraManager)
///     .ignoresSafeArea()
/// ```
struct CameraPreviewView: UIViewRepresentable {

    let cameraManager: CameraManager

    // MARK: UIViewRepresentable

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // The preview layer is set asynchronously after the session starts —
        // guard against the brief window where it is still nil.
        if let layer = cameraManager.previewLayer {
            uiView.setPreviewLayer(layer)
        }
    }
}

// MARK: - PreviewUIView

/// Internal UIView subclass that owns an `AVCaptureVideoPreviewLayer` as a sublayer.
///
/// The layer is always pinned to `bounds` so it fills the view on every layout pass,
/// which correctly handles device rotation and split-screen transitions.
final class PreviewUIView: UIView {

    // MARK: Private State

    private var currentLayer: AVCaptureVideoPreviewLayer?

    // MARK: Layer Management

    /// Attaches `layer` as the bottom-most sublayer of this view.
    ///
    /// - If the same layer is already attached, the call is a no-op.
    /// - Removes the previously attached layer before inserting the new one.
    func setPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        guard layer !== currentLayer else { return }

        currentLayer?.removeFromSuperlayer()

        layer.frame = bounds
        layer.videoGravity = .resizeAspectFill
        // Insert at index 0 so any future SwiftUI overlay sublayers sit on top.
        self.layer.insertSublayer(layer, at: 0)

        currentLayer = layer
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // Keep the preview layer in sync when the view resizes.
        currentLayer?.frame = bounds
    }
}
