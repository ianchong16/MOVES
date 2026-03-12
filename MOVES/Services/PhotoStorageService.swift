import Foundation
import UIKit

// MARK: - Photo Storage Service
// Saves move journal photos as UUID-named JPEGs in the app's Documents directory.
// Photos are never stored in SwiftData — binary blobs in SQLite degrade performance.
// The Move model stores only the filename string; this service handles the actual bytes.
// Documents directory is included in iCloud backup automatically.

struct PhotoStorageService {

    // MARK: - Documents Directory
    private static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Save
    // Compresses image to JPEG, writes to Documents/moveID.jpg.
    // Returns the filename on success, nil on failure.
    @discardableResult
    static func save(image: UIImage, for moveID: UUID) -> String? {
        let filename = "\(moveID.uuidString).jpg"
        let fileURL = documentsURL.appendingPathComponent(filename)

        guard let data = image.jpegData(compressionQuality: 0.75) else {
            print("[Photos] ❌ Could not compress image for \(moveID)")
            return nil
        }

        do {
            try data.write(to: fileURL)
            print("[Photos] ✅ Saved \(filename) (\(data.count / 1024) KB)")
            return filename
        } catch {
            print("[Photos] ❌ Write failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Load
    // Returns the UIImage for a given filename, or nil if not found.
    static func load(filename: String) -> UIImage? {
        let fileURL = documentsURL.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("[Photos] ⚠️ File not found: \(filename)")
            return nil
        }
        return UIImage(contentsOfFile: fileURL.path)
    }

    // MARK: - Delete
    // Removes the photo file. Call when a journal entry is deleted.
    static func delete(filename: String) {
        let fileURL = documentsURL.appendingPathComponent(filename)
        do {
            try FileManager.default.removeItem(at: fileURL)
            print("[Photos] 🗑 Deleted \(filename)")
        } catch {
            print("[Photos] ⚠️ Delete failed: \(error.localizedDescription)")
        }
    }
}
