import UIKit

enum ImageCompressor {
    /// Downscales to max 2048 px and re-encodes as JPEG so photos stay small in the store and backups.
    static func jpeg(from data: Data, maxDimension: CGFloat = 2048, quality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    /// Adds picked photos, compressed, up to `limit`. `failed` says that at least one could not be loaded
    /// (nil in `loaded`), so the editor can tell instead of skipping it silently.
    static func adding(_ loaded: [Data?], to photos: [Data], limit: Int = Limits.maxPhotos) -> (photos: [Data], failed: Bool) {
        let room = max(0, limit - photos.count)
        let added = loaded.compactMap { $0 }.prefix(room).map { jpeg(from: $0) ?? $0 }
        return (photos + added, loaded.contains(nil))
    }
}
