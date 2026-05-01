import AVFoundation
import Foundation
import SwiftData
import UIKit

// MARK: - VideoError

enum VideoError: Error {
    case noContainer
    case copyFailed
    case analysisFailed
}

// MARK: - VideoRepository

/// Manages persistence and file-system operations for `VideoSession` records.
///
/// `modelContainer` must be injected by `KineticsApp` before any method is
/// called. All methods are synchronous on `@MainActor` except
/// `generateThumbnail`, which is `async`.
@MainActor
final class VideoRepository {

    static let shared = VideoRepository()

    /// Injected by `KineticsApp.onAppear` — see `KineticsApp.swift`.
    var modelContainer: ModelContainer?

    // MARK: - Private helpers

    private var context: ModelContext {
        get throws {
            guard let container = modelContainer else { throw VideoError.noContainer }
            return container.mainContext
        }
    }

    // MARK: - CRUD

    func save(_ session: VideoSession) throws {
        let ctx = try context
        ctx.insert(session)
        try ctx.save()
    }

    func fetchAll(userId: String) throws -> [VideoSession] {
        let ctx = try context
        let descriptor = FetchDescriptor<VideoSession>(
            sortBy: [SortDescriptor(\VideoSession.recordedAt, order: .reverse)]
        )
        let all = try ctx.fetch(descriptor)
        return all.filter { $0.userId == userId }
    }

    func fetchBySport(userId: String, sport: VideoSport) throws -> [VideoSession] {
        try fetchAll(userId: userId).filter { $0.videoSport == sport }
    }

    func delete(_ session: VideoSession) throws {
        let ctx = try context
        // Remove the local video file before deleting the record.
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videoURL = docsURL.appendingPathComponent(session.localVideoPath)
        try? FileManager.default.removeItem(at: videoURL)
        ctx.delete(session)
        try ctx.save()
    }

    func update(_ session: VideoSession) throws {
        let ctx = try context
        try ctx.save()
    }

    // MARK: - File storage

    /// Copies a video from the picker's temporary URL into the app's Documents
    /// directory and returns the relative path to store in `VideoSession.localVideoPath`.
    func copyVideoToDocuments(from sourceURL: URL) throws -> String {
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videosDir = docsURL.appendingPathComponent("KineticsVideos", isDirectory: true)
        try FileManager.default.createDirectory(at: videosDir, withIntermediateDirectories: true)

        let filename = "\(UUID().uuidString).mov"
        let destURL = videosDir.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: sourceURL, to: destURL)
        return "KineticsVideos/\(filename)"
    }

    /// Returns the full Documents-relative URL for a stored video, or `nil` if
    /// the file no longer exists on disk.
    func videoURL(for session: VideoSession) -> URL? {
        guard !session.localVideoPath.isEmpty else { return nil }
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docsURL.appendingPathComponent(session.localVideoPath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Thumbnail

    /// Generates a JPEG thumbnail from the first second of the video.
    /// Returns `nil` if the frame cannot be decoded.
    func generateThumbnail(from videoURL: URL) async -> Data? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)

        let time = CMTime(seconds: 1, preferredTimescale: 600)
        return await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { image, _, _ in
                if let image {
                    let uiImage = UIImage(cgImage: image)
                    continuation.resume(returning: uiImage.jpegData(compressionQuality: 0.7))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
