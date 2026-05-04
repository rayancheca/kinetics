import AVFoundation
import Foundation
import Observation
import PhotosUI
import SwiftData
import UIKit
import Vision

// MARK: - FaceSetupViewModel

/// Drives the face-enrolment flow.
///
/// Threading model:
/// - `@Observable @MainActor` keeps all UI-facing state on the main thread.
/// - Vision work is delegated to `FaceProfileEngine.shared` (an actor), so every
///   `await` call hops off the main thread without any manual `Task.detached`.
/// - SwiftData mutations happen through the injected `ModelContext`, which must be
///   created on the main thread by the caller (e.g. via `@Environment(\.modelContext)`).
@Observable
@MainActor
final class FaceSetupViewModel {

    // MARK: - Phase

    /// Describes where the user is in the face-scan onboarding flow.
    enum ScanPhase {
        /// Waiting for the user to initiate a scan.
        case idle
        /// Camera is active; Vision is searching for a face.
        case scanning
        /// Feature print is being computed.
        case processing
        /// Face scanned and saved successfully. Associated value is the face preview image.
        case success(UIImage)
        /// Something went wrong. Associated value is a user-friendly message.
        case failed(String)
    }

    // MARK: - State

    /// Current step in the onboarding flow.
    private(set) var phase: ScanPhase = .idle

    /// How many scan attempts remain before the fallback options are surfaced.
    private(set) var triesRemaining: Int = 2

    /// The most recently captured or selected image (before processing).
    var capturedImage: UIImage?

    /// `true` once a `FaceProfile` has been successfully persisted to SwiftData.
    private(set) var isSaved = false

    // MARK: - Actions

    // MARK: Start

    /// Transitions the flow from `.idle` to `.scanning`.
    ///
    /// Call this when the user taps the "Begin Scan" / "Scan My Face" button.
    /// The view is responsible for presenting the camera picker once this is called.
    func startScan() {
        phase = .scanning
    }

    // MARK: Process Camera Photo

    /// Processes a photo captured directly from the camera.
    ///
    /// - Parameters:
    ///   - image: A `UIImage` produced by the camera picker.
    ///   - userId: Firebase Auth UID of the current user.
    ///   - modelContext: A `ModelContext` on the main actor (from `@Environment(\.modelContext)`).
    func processCapturedPhoto(
        _ image: UIImage,
        userId: String,
        modelContext: ModelContext
    ) async {
        await processImage(image, userId: userId, modelContext: modelContext)
    }

    // MARK: Process Photo Library Photo

    /// Processes an image the user selected from their photo library.
    ///
    /// - Parameters:
    ///   - image: A `UIImage` loaded from `PhotosPickerItem`.
    ///   - userId: Firebase Auth UID of the current user.
    ///   - modelContext: A `ModelContext` on the main actor (from `@Environment(\.modelContext)`).
    func processPickedPhoto(
        _ image: UIImage,
        userId: String,
        modelContext: ModelContext
    ) async {
        await processImage(image, userId: userId, modelContext: modelContext)
    }

    // MARK: Retry

    /// Resets back to `.scanning` so the user can try again.
    ///
    /// Call when the user taps "Try Again" after a failure. `triesRemaining` is not
    /// incremented — retries only count down, not up.
    func retry() {
        capturedImage = nil
        phase = .scanning
    }

    // MARK: Skip

    /// Transitions the user to the manual tap-to-identify path.
    ///
    /// When called, the view should dismiss this sheet and skip face setup entirely.
    /// The caller is responsible for marking the onboarding step as skipped.
    func useManualIdentification() {
        phase = .idle
    }

    // MARK: Query

    /// Fetches the existing `FaceProfile` for `userId`, or `nil` if none exists yet.
    ///
    /// - Parameters:
    ///   - userId: Firebase Auth UID of the current user.
    ///   - modelContext: A `ModelContext` on the main actor.
    func existingProfile(userId: String, modelContext: ModelContext) -> FaceProfile? {
        let predicate = #Predicate<FaceProfile> { $0.userId == userId }
        let descriptor = FetchDescriptor<FaceProfile>(predicate: predicate)
        return (try? modelContext.fetch(descriptor))?.first
    }

    // MARK: Delete

    /// Deletes the stored `FaceProfile` for `userId` and resets all local state.
    ///
    /// - Parameters:
    ///   - userId: Firebase Auth UID of the current user.
    ///   - modelContext: A `ModelContext` on the main actor.
    func deleteFaceProfile(userId: String, modelContext: ModelContext) {
        let predicate = #Predicate<FaceProfile> { $0.userId == userId }
        let descriptor = FetchDescriptor<FaceProfile>(predicate: predicate)
        if let profiles = try? modelContext.fetch(descriptor) {
            for profile in profiles {
                modelContext.delete(profile)
            }
            try? modelContext.save()
        }
        capturedImage = nil
        isSaved = false
        triesRemaining = 2
        phase = .idle
    }

    // MARK: - Private: Core Processing

    /// Shared implementation for both camera and library paths.
    private func processImage(
        _ image: UIImage,
        userId: String,
        modelContext: ModelContext
    ) async {
        phase = .processing

        do {
            let result = try await FaceProfileEngine.shared.scanFace(from: image)

            // Build and persist the FaceProfile.
            let profile = FaceProfile(
                userId: userId,
                displayName: "You",
                photoData: result.croppedFaceData,
                featurePrintData: result.featurePrintData
            )
            modelContext.insert(profile)
            try modelContext.save()
            isSaved = true

            // Build a preview UIImage for the success state from the saved JPEG.
            let previewImage = UIImage(data: result.croppedFaceData) ?? image
            phase = .success(previewImage)

        } catch FaceProfileError.noFaceDetected {
            handleNoFaceDetected()

        } catch FaceProfileError.multipleFacesDetected {
            phase = .failed("Multiple faces detected. Please scan alone.")

        } catch FaceProfileError.lowConfidence(let score) {
            phase = .failed(
                String(
                    format: "Detection confidence too low (%.0f%%). "
                        + "Try better lighting or move closer.",
                    score * 100
                )
            )

        } catch {
            // Covers featurePrintFailed, serialisationFailed, and any unexpected errors.
            phase = .failed("Something went wrong. Please try again.")
        }
    }

    /// Handles the no-face-detected case, decrementing retries and surfacing the
    /// appropriate message based on how many attempts remain.
    private func handleNoFaceDetected() {
        triesRemaining -= 1

        if triesRemaining > 0 {
            phase = .failed(
                "We couldn't find your face. Make sure you're:\n"
                    + "• In good lighting\n"
                    + "• Looking straight at the camera\n"
                    + "• Close enough to fill the frame"
            )
        } else {
            phase = .failed(
                "Camera angle too difficult. Upload a clear photo of your face "
                    + "or use tap-to-identify below."
            )
        }
    }
}
