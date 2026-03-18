import Foundation
import UIKit
import AVFoundation

// MARK: - Video Storage Service
// Mirrors PhotoStorageService pattern for short video clips (≤15 seconds).
// Videos saved as .mov files in Documents directory.
// SwiftData stores only the filename string — no binary blobs.

struct VideoStorageService {

    // MARK: - Documents Directory
    private static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Save
    // Copies video from temp URL to Documents/{moveID}.mov.
    // Compresses to medium quality (720p) to keep file sizes reasonable (~5-10 MB for 15s).
    // Returns filename on success, nil on failure.
    @discardableResult
    static func save(videoURL: URL, for moveID: UUID) async -> String? {
        let filename = "\(moveID.uuidString).mov"
        let destinationURL = documentsURL.appendingPathComponent(filename)

        // Compress to medium quality
        let asset = AVURLAsset(url: videoURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            // Fallback: direct copy without compression
            return copyFile(from: videoURL, to: destinationURL, filename: filename)
        }

        exportSession.outputURL = destinationURL
        exportSession.outputFileType = .mov
        exportSession.shouldOptimizeForNetworkUse = true

        // Trim to 15 seconds max
        let duration = try? await asset.load(.duration)
        if let duration, CMTimeGetSeconds(duration) > 15.0 {
            let trimRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 15.0, preferredTimescale: 600))
            exportSession.timeRange = trimRange
        }

        // Remove existing file if present
        try? FileManager.default.removeItem(at: destinationURL)

        await exportSession.export()

        if exportSession.status == .completed {
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as? Int) ?? 0
            print("[Video] \u{2705} Saved \(filename) (\(fileSize / 1024) KB)")
            return filename
        } else {
            let error = exportSession.error?.localizedDescription ?? "unknown"
            print("[Video] \u{274C} Export failed: \(error) — falling back to copy")
            return copyFile(from: videoURL, to: destinationURL, filename: filename)
        }
    }

    // MARK: - Load
    // Returns the file URL for a given filename, or nil if not found.
    static func load(filename: String) -> URL? {
        let fileURL = documentsURL.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("[Video] \u{26A0}\u{FE0F} File not found: \(filename)")
            return nil
        }
        return fileURL
    }

    // MARK: - Delete
    static func delete(filename: String) {
        let fileURL = documentsURL.appendingPathComponent(filename)
        do {
            try FileManager.default.removeItem(at: fileURL)
            print("[Video] \u{1F5D1} Deleted \(filename)")
        } catch {
            print("[Video] \u{26A0}\u{FE0F} Delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Generate Thumbnail
    // Extracts a frame at 0.5s for preview thumbnails.
    static func generateThumbnail(filename: String) -> UIImage? {
        guard let fileURL = load(filename: filename) else { return nil }
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)

        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        do {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            print("[Video] \u{26A0}\u{FE0F} Thumbnail generation failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Duration
    // Returns video duration in seconds.
    static func duration(filename: String) async -> Double? {
        guard let fileURL = load(filename: filename) else { return nil }
        let asset = AVURLAsset(url: fileURL)
        guard let duration = try? await asset.load(.duration) else { return nil }
        return CMTimeGetSeconds(duration)
    }

    // MARK: - Helpers
    private static func copyFile(from source: URL, to destination: URL, filename: String) -> String? {
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int) ?? 0
            print("[Video] \u{2705} Copied \(filename) (\(fileSize / 1024) KB)")
            return filename
        } catch {
            print("[Video] \u{274C} Copy failed: \(error.localizedDescription)")
            return nil
        }
    }
}
