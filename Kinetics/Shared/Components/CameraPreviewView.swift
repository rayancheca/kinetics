import SwiftUI
import UIKit
import AVFoundation

// MARK: - CameraPreviewView

/// A SwiftUI wrapper around `AVCaptureVideoPreviewLayer` that fills its parent
/// with the live camera feed. Uses `UIViewRepresentable` because SwiftUI has no
/// native layer-level API for AVFoundation preview layers.
///
/// Pass `previewLayer` directly (not the whole `CameraManager`) so SwiftUI
/// tracks the property during body evaluation and calls `updateUIView` as soon
/// as the layer becomes non-nil after the async camera start.
///
/// Usage:
/// ```swift
/// CameraPreviewView(previewLayer: cameraManager.previewLayer)
///     .ignoresSafeArea()
/// ```
struct CameraPreviewView: UIViewRepresentable {

    let previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: UIViewRepresentable

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if let layer = previewLayer {
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
