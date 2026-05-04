import AVFoundation
import FirebaseStorage
import Foundation

// MARK: - VideoStorageError

enum VideoStorageError: LocalizedError {
    case uploadFailed
    case downloadFailed
    case deleteFailed
    case fileNotFound
    case invalidURL
    case premiumRequired

    var errorDescription: String? {
        switch self {
        case .uploadFailed:    return "Video upload failed."
        case .downloadFailed:  return "Video download failed."
        case .deleteFailed:    return "Video deletion failed."
        case .fileNotFound:    return "The video file could not be found."
        case .invalidURL:      return "The provided URL is invalid."
        case .premiumRequired: return "A premium subscription is required to use video storage."
        }
    }
}

// MARK: - VideoStorageService

/// Handles upload, download, deletion, and thumbnail operations for workout videos
/// stored in Firebase Storage.
///
/// All paths follow the convention:
///   - Videos:     `videos/{userId}/{videoId}.mp4`
///   - Thumbnails: `thumbnails/{userId}/{videoId}.jpg`
actor VideoStorageService {

    // MARK: - Shared instance

    static let shared = VideoStorageService()

    // MARK: - Premium gate

    /// Set to `false` once StoreKit 2 integration is complete so that only
    /// premium subscribers can access cloud video storage.
    nonisolated(unsafe) static var isPremiumEnabled: Bool = true

    // MARK: - Constants

    private enum Constant {
        /// Files larger than this (in bytes) are compressed before upload.
        static let compressionThresholdBytes: Int64 = 200 * 1024 * 1024 // 200 MB
        static let videoContentType = "video/mp4"
        static let thumbnailContentType = "image/jpeg"
    }

    // MARK: - Private helpers

    private var storage: Storage { Storage.storage() }

    private func videoRef(userId: String, videoId: String) -> StorageReference {
        storage.reference().child("videos/\(userId)/\(videoId).mp4")
    }

    private func thumbnailRef(userId: String, videoId: String) -> StorageReference {
        storage.reference().child("thumbnails/\(userId)/\(videoId).jpg")
    }

    // MARK: - Upload

    /// Uploads a video file to Firebase Storage.
    ///
    /// Files larger than 200 MB are compressed to 720p before uploading.
    /// Progress is reported via `progressHandler` (0.0 – 1.0).
    ///
    /// - Returns: The download URL string for the uploaded video.
    func uploadVideo(
        localURL: URL,
        userId: String,
        videoId: String,
        progressHandler: @Sendable @escaping (Double) -> Void
    ) async throws -> String {
        guard VideoStorageService.isPremiumEnabled else {
            throw VideoStorageError.premiumRequired
        }

        let sourceURL = try await compressIfNeeded(url: localURL)
        defer { cleanUpTempFile(at: sourceURL, originalURL: localURL) }

        let ref = videoRef(userId: userId, videoId: videoId)
        let metadata = StorageMetadata()
        metadata.contentType = Constant.videoContentType

        let downloadURLString: String = try await withCheckedThrowingContinuation { continuation in
            let uploadTask = ref.putFile(from: sourceURL, metadata: metadata)

            uploadTask.observe(.progress) { snapshot in
                let completed = Double(snapshot.progress?.completedUnitCount ?? 0)
                let total = Double(snapshot.progress?.totalUnitCount ?? 1)
                let fraction = total > 0 ? completed / total : 0.0
                progressHandler(fraction)
            }

            uploadTask.observe(.success) { _ in
                ref.downloadURL { url, error in
                    if let url {
                        continuation.resume(returning: url.absoluteString)
                    } else {
                        continuation.resume(throwing: error ?? VideoStorageError.uploadFailed)
                    }
                }
            }

            uploadTask.observe(.failure) { snapshot in
                continuation.resume(
                    throwing: snapshot.error ?? VideoStorageError.uploadFailed
                )
            }
        }

        return downloadURLString
    }

    // MARK: - Download

    /// Downloads a video from Firebase Storage to a local temporary URL.
    ///
    /// - Returns: The local file URL of the downloaded video.
    func downloadVideo(
        cloudURL: String,
        videoId: String
    ) async throws -> URL {
        guard VideoStorageService.isPremiumEnabled else {
            throw VideoStorageError.premiumRequired
        }

        guard let _ = URL(string: cloudURL) else {
            throw VideoStorageError.invalidURL
        }

        let ref = Storage.storage().reference(forURL: cloudURL)
        let destinationURL = temporaryURL(for: videoId, extension: "mp4")

        return try await withCheckedThrowingContinuation { continuation in
            ref.write(toFile: destinationURL) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(
                        throwing: error ?? VideoStorageError.downloadFailed
                    )
                }
            }
        }
    }

    // MARK: - Delete

    /// Deletes a video from Firebase Storage.
    func deleteVideo(userId: String, videoId: String) async throws {
        guard VideoStorageService.isPremiumEnabled else {
            throw VideoStorageError.premiumRequired
        }

        let ref = videoRef(userId: userId, videoId: videoId)

        return try await withCheckedThrowingContinuation { continuation in
            ref.delete { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Thumbnail Upload

    /// Uploads a JPEG thumbnail to `thumbnails/{userId}/{videoId}.jpg`.
    ///
    /// - Returns: The download URL string for the uploaded thumbnail.
    func uploadThumbnail(
        thumbnailData: Data,
        userId: String,
        videoId: String
    ) async throws -> String {
        guard VideoStorageService.isPremiumEnabled else {
            throw VideoStorageError.premiumRequired
        }

        let ref = thumbnailRef(userId: userId, videoId: videoId)
        let metadata = StorageMetadata()
        metadata.contentType = Constant.thumbnailContentType

        return try await withCheckedThrowingContinuation { continuation in
            let uploadTask = ref.putData(thumbnailData, metadata: metadata)

            uploadTask.observe(.success) { _ in
                ref.downloadURL { url, error in
                    if let url {
                        continuation.resume(returning: url.absoluteString)
                    } else {
                        continuation.resume(
                            throwing: error ?? VideoStorageError.uploadFailed
                        )
                    }
                }
            }

            uploadTask.observe(.failure) { snapshot in
                continuation.resume(
                    throwing: snapshot.error ?? VideoStorageError.uploadFailed
                )
            }
        }
    }

    // MARK: - Size Check

    /// Returns the size in bytes of a local file.
    ///
    /// - Returns: The file size, or `0` if the file does not exist.
    func fileSize(at url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return 0
        }
        return size
    }

    // MARK: - Private: Compression

    /// Compresses a video to 720p if it exceeds the 200 MB threshold.
    ///
    /// - Returns: The original URL if no compression is needed, or a new temp URL
    ///   containing the compressed output.
    private func compressIfNeeded(url: URL) async throws -> URL {
        let size = fileSize(at: url)
        guard size > Constant.compressionThresholdBytes else {
            return url
        }

        let asset = AVURLAsset(url: url)
        let outputURL = temporaryURL(for: UUID().uuidString, extension: "mp4")

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPreset1280x720
        ) else {
            // Compression not possible — fall back to original.
            return url
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        await exportSession.export()

        switch exportSession.status {
        case .completed:
            return outputURL
        default:
            // If export fails for any reason, attempt upload with the original.
            return url
        }
    }

    // MARK: - Private: Temp file utilities

    private func temporaryURL(for name: String, extension ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
            .appendingPathExtension(ext)
    }

    /// Removes a compressed temp file only when it differs from the original.
    private func cleanUpTempFile(at tempURL: URL, originalURL: URL) {
        guard tempURL != originalURL else { return }
        try? FileManager.default.removeItem(at: tempURL)
    }
}
