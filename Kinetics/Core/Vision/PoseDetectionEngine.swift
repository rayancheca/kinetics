@preconcurrency import AVFoundation
import Vision

// MARK: - PoseError

enum PoseError: LocalizedError, Sendable {
    case processingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .processingFailed(let underlying):
            "Pose detection failed: \(underlying.localizedDescription)"
        }
    }
}

// MARK: - PoseDetectionEngine

/// An actor that processes raw video frames and extracts a full 19-joint body pose for each.
///
/// **Design notes:**
/// - Using `actor` (not `@MainActor`) isolates the Vision work on its own serial executor,
///   keeping the main thread free for SwiftUI rendering.
/// - `VNSequenceRequestHandler` is reused across frames for temporal consistency — Vision uses
///   frame history to improve joint localization over time.
/// - The request object is also reused; results are read after each `perform` call and the
///   request's `results` property is reset automatically on the next call.
/// - Empty detections (no person in frame) return `nil` rather than throwing — this is expected
///   and normal; callers should treat `nil` as "no person detected this frame".
actor PoseDetectionEngine {

    // MARK: - Private

    /// Maintains frame sequence history for temporal smoothing across calls.
    /// Declared `var` so `reset()` can replace it and discard accumulated temporal state.
    private var sequenceHandler = VNSequenceRequestHandler()

    /// Reused request object — creating it once avoids per-frame allocation overhead.
    private let poseRequest: VNDetectHumanBodyPoseRequest

    // MARK: - Init

    init() {
        poseRequest = VNDetectHumanBodyPoseRequest()
    }

    // MARK: - Public API

    /// Processes one video frame and returns a `JointPose` if a body was detected.
    ///
    /// - Parameters:
    ///   - buffer: A `CMSampleBuffer` from `CameraManager.frameStream`.
    ///   - isFrontCamera: When `true`, the joint x-coordinates are mirrored (1 - x) to
    ///     correct for the fact that Vision's output is not flipped even though the preview
    ///     layer is. Pass `cameraManager.cameraPosition == .front` from the ViewModel.
    /// - Returns: A `JointPose` with all detected joint positions, or `nil` when no person
    ///   is visible in the frame.
    /// - Throws: `PoseError.processingFailed` when Vision's request handler encounters an
    ///   unrecoverable error (e.g. invalid pixel format). Empty frames never throw.
    func process(_ buffer: CMSampleBuffer, isFrontCamera: Bool = false) throws -> JointPose? {
        do {
            // `orientation: .up` matches the 90° rotation applied in CameraManager.
            try sequenceHandler.perform([poseRequest], on: buffer, orientation: .up)
        } catch {
            throw PoseError.processingFailed(error)
        }

        // `results` is nil or empty when no person is detected — return nil, not an error.
        guard let observation = poseRequest.results?.first else {
            return nil
        }

        // JointPose(from:) extracts all recognized points from the observation.
        var pose = try JointPose(from: observation)

        // When using the front camera, Vision coordinates are NOT mirrored even though
        // the preview layer is. Flip x so skeleton overlays line up with what the user sees.
        if isFrontCamera {
            pose = pose.mirroredHorizontally()
        }

        return pose
    }

    /// Resets internal sequence state.
    ///
    /// Call this when switching sports modules or after a significant gap in frames
    /// (e.g. the user left the camera view). Replaces the sequence handler so the next
    /// frame starts with a clean temporal baseline rather than stale history from a
    /// different movement context.
    func reset() {
        sequenceHandler = VNSequenceRequestHandler()
    }
}
