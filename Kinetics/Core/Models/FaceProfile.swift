import Foundation
import SwiftData

// MARK: - FaceProfile

/// Persisted record linking a face feature-print to a display name for a subject
/// detected in a workout video. `featurePrintData` holds an
/// `NSKeyedArchiver`-encoded `VNFeaturePrintObservation` so that re-identification
/// can be done without re-encoding the original image.
///
/// `photoData` is a compressed JPEG crop used solely for display purposes in the
/// session review UI — it is not used in any biometric comparison.
@Model
final class FaceProfile {

    // MARK: - Stored Properties

    var id: String
    var userId: String
    var capturedAt: Date
    var photoData: Data?         // Compressed JPEG of face crop (display only)
    var featurePrintData: Data?  // NSKeyedArchiver-encoded VNFeaturePrintObservation
    var displayName: String      // User-visible label; defaults to "You"

    // MARK: - Init

    init(
        id: String = UUID().uuidString,
        userId: String,
        displayName: String = "You",
        capturedAt: Date = Date(),
        photoData: Data? = nil,
        featurePrintData: Data? = nil
    ) {
        self.id = id
        self.userId = userId
        self.displayName = displayName
        self.capturedAt = capturedAt
        self.photoData = photoData
        self.featurePrintData = featurePrintData
    }
}

// MARK: - Convenience Factories

extension FaceProfile {

    /// Creates a placeholder `FaceProfile` representing the app owner ("You")
    /// before any face data has been captured. `featurePrintData` is `nil` until
    /// the user completes the face-enrolment flow.
    static func ownerPlaceholder(userId: String) -> FaceProfile {
        FaceProfile(
            userId: userId,
            displayName: "You"
        )
    }
}
