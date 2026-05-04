import CoreImage
import Foundation
import UIKit
import Vision

// MARK: - FaceScanResult

/// The output of a successful face scan: a compressed JPEG crop, a serialised
/// `VNFeaturePrintObservation` for later comparison, and the normalised face rect.
struct FaceScanResult: Sendable {
    /// JPEG-compressed face crop — used for display only, not biometric comparison.
    let croppedFaceData: Data
    /// `NSKeyedArchiver`-encoded `VNFeaturePrintObservation` used for re-identification.
    let featurePrintData: Data
    /// Normalised face bounding box in the original image coordinate space.
    let boundingBox: CGRect
}

// MARK: - FaceProfileError

enum FaceProfileError: LocalizedError {
    case noFaceDetected
    case multipleFacesDetected
    case lowConfidence(Double)
    case featurePrintFailed
    case serialisationFailed

    var errorDescription: String? {
        switch self {
        case .noFaceDetected:
            return "No face was detected in the image."
        case .multipleFacesDetected:
            return "Multiple faces detected. Please scan alone."
        case .lowConfidence(let score):
            return String(format: "Face detection confidence too low (%.0f%%).", score * 100)
        case .featurePrintFailed:
            return "Could not generate a feature print for the face."
        case .serialisationFailed:
            return "Failed to serialise the face feature print."
        }
    }
}

// MARK: - FaceProfileEngine

/// An `actor` that wraps Apple's Vision Framework for face detection and identification.
///
/// All Vision work executes on the actor's serial executor, keeping the main thread free.
/// Use `FaceProfileEngine.shared` from any isolation context via `await`.
actor FaceProfileEngine {

    // MARK: - Shared Instance

    static let shared = FaceProfileEngine()

    // MARK: - Constants

    /// Distance threshold for `VNFeaturePrintObservation.computeDistance(_:to:)`.
    /// A value of 0.0 means identical; values below this threshold are treated as a match.
    private let matchThreshold: Float = 0.75

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    /// Scans a face from `image`, extracts a feature print, and returns a `FaceScanResult`.
    ///
    /// - Throws: `FaceProfileError.noFaceDetected` when Vision finds no face.
    /// - Throws: `FaceProfileError.multipleFacesDetected` when Vision finds more than one face.
    /// - Throws: `FaceProfileError.featurePrintFailed` when the feature print cannot be generated.
    /// - Throws: `FaceProfileError.serialisationFailed` when archiving the print fails.
    func scanFace(from image: UIImage) async throws -> FaceScanResult {
        guard let cgImage = image.cgImage else {
            throw FaceProfileError.noFaceDetected
        }

        // Step 1 — detect face rectangles.
        let faceObservations = try detectFaceObservations(in: cgImage)

        guard !faceObservations.isEmpty else {
            throw FaceProfileError.noFaceDetected
        }
        guard faceObservations.count == 1 else {
            throw FaceProfileError.multipleFacesDetected
        }

        let observation = faceObservations[0]

        // Step 2 — crop the face from the original image.
        let cropRect = normalizedRectToPixelRect(
            observation.boundingBox,
            imageSize: CGSize(width: cgImage.width, height: cgImage.height)
        )

        guard let faceCGImage = cgImage.cropping(to: cropRect) else {
            throw FaceProfileError.featurePrintFailed
        }

        // Step 3 — generate feature print from the cropped face.
        guard let featurePrint = try generateFeaturePrint(from: faceCGImage) else {
            throw FaceProfileError.featurePrintFailed
        }

        // Step 4 — serialise the feature print.
        guard let printData = try? NSKeyedArchiver.archivedData(
            withRootObject: featurePrint,
            requiringSecureCoding: false
        ) else {
            throw FaceProfileError.serialisationFailed
        }

        // Step 5 — compress the face crop to JPEG.
        let faceUIImage = UIImage(cgImage: faceCGImage)
        guard let jpegData = faceUIImage.jpegData(compressionQuality: 0.85) else {
            throw FaceProfileError.serialisationFailed
        }

        return FaceScanResult(
            croppedFaceData: jpegData,
            featurePrintData: printData,
            boundingBox: observation.boundingBox
        )
    }

    /// Generates a serialised feature print from `imageData` cropped to `faceRegion`.
    ///
    /// - Parameters:
    ///   - imageData: Raw image bytes (JPEG, PNG, etc.) representing a video frame or photo.
    ///   - faceRegion: Pixel-space rect within the image to crop before generating the print.
    /// - Returns: `NSKeyedArchiver`-encoded `VNFeaturePrintObservation`, or `nil` when no
    ///   feature print could be generated (e.g. the region is too small or featureless).
    func featurePrint(from imageData: Data, faceRegion: CGRect) async -> Data? {
        guard
            let uiImage = UIImage(data: imageData),
            let cgImage = uiImage.cgImage,
            let faceCrop = cgImage.cropping(to: faceRegion),
            let print = try? generateFeaturePrint(from: faceCrop)
        else {
            return nil
        }
        return try? NSKeyedArchiver.archivedData(
            withRootObject: print,
            requiringSecureCoding: false
        )
    }

    /// Identifies whether the face in `frameImage` matches the stored profile.
    ///
    /// Algorithm:
    /// 1. Detect all faces in the frame.
    /// 2. For each face, generate a feature print and compare to `storedPrintData`.
    /// 3. The face whose distance to the stored print is lowest and below `matchThreshold`
    ///    is labelled "You". Other detected faces are labelled "Person 2".
    ///
    /// - Parameters:
    ///   - frameImage: A `CIImage` video frame to analyse.
    ///   - storedPrintData: Archived `VNFeaturePrintObservation` from the user's profile,
    ///     or `nil` when the user has not enrolled a face yet.
    /// - Returns: A tuple `(label, confidence)` where `confidence` is in `[0, 1]`.
    func identifySubject(
        in frameImage: CIImage,
        storedPrintData: Data?
    ) async -> (label: String, confidence: Double) {
        // Convert CIImage → CGImage for Vision requests that require CGImage input.
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(frameImage, from: frameImage.extent) else {
            return ("Unknown", 0)
        }

        // Detect face rectangles.
        guard let faceObs = try? detectFaceObservations(in: cgImage),
              !faceObs.isEmpty else {
            return ("Unknown", 0)
        }

        // Deserialise stored print once (outside the per-face loop).
        let storedPrint: VNFeaturePrintObservation?
        if let data = storedPrintData {
            storedPrint = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: VNFeaturePrintObservation.self,
                from: data
            )
        } else {
            storedPrint = nil
        }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

        // Evaluate each face.
        var bestDistance: Float = Float.greatestFiniteMagnitude
        var bestLabel = "Person 2"
        var bestConfidence = 0.0

        for obs in faceObs {
            let cropRect = normalizedRectToPixelRect(obs.boundingBox, imageSize: imageSize)
            guard
                let faceCrop = cgImage.cropping(to: cropRect),
                let facePrint = try? generateFeaturePrint(from: faceCrop)
            else {
                continue
            }

            guard let stored = storedPrint else {
                // No profile enrolled — we can only say a face exists, not who it is.
                return ("Person 2", 0)
            }

            var distance: Float = 0
            guard (try? stored.computeDistance(&distance, to: facePrint)) != nil else {
                continue
            }

            if distance < bestDistance {
                bestDistance = distance
                if distance < matchThreshold {
                    bestLabel = "You"
                    bestConfidence = Double(1.0 - distance)
                } else {
                    bestLabel = "Person 2"
                    bestConfidence = 0
                }
            }
        }

        return (bestLabel, bestConfidence)
    }

    /// Returns normalised bounding boxes for all faces detected in `image`.
    ///
    /// Coordinates follow Vision's convention: origin at bottom-left, normalised to `[0, 1]`.
    func detectFaces(in image: CIImage) async -> [CGRect] {
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            return []
        }
        let observations = (try? detectFaceObservations(in: cgImage)) ?? []
        return observations.map { $0.boundingBox }
    }

    // MARK: - Private Helpers

    /// Runs `VNDetectFaceRectanglesRequest` on `cgImage` and returns the observations.
    private func detectFaceObservations(
        in cgImage: CGImage
    ) throws -> [VNFaceObservation] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        return request.results ?? []
    }

    /// Runs `VNGenerateImageFeaturePrintRequest` on `cgImage` and returns the first result.
    private func generateFeaturePrint(
        from cgImage: CGImage
    ) throws -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        return request.results?.first
    }

    /// Converts a Vision normalised bounding box (origin bottom-left) to a pixel-space
    /// `CGRect` whose origin is top-left, suitable for `CGImage.cropping(to:)`.
    ///
    /// Vision's Y axis is flipped relative to UIKit/CoreGraphics:
    /// - Vision: (0, 0) = bottom-left
    /// - CoreGraphics: (0, 0) = top-left
    private func normalizedRectToPixelRect(_ normalized: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(
            x: normalized.origin.x * imageSize.width,
            y: (1 - normalized.origin.y - normalized.height) * imageSize.height,
            width: normalized.width * imageSize.width,
            height: normalized.height * imageSize.height
        )
    }
}
