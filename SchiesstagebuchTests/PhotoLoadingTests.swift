import XCTest
import UIKit
@testable import Schiesstagebuch

final class PhotoLoadingTests: XCTestCase {
    private let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { ctx in
        UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
    }.pngData()!

    func testAddsLoadedPhotosAndReportsAFailure() {
        let (photos, failed) = ImageCompressor.adding([image, nil, image], to: [])
        XCTAssertEqual(photos.count, 2, "the photo that failed to load is left out")
        XCTAssertTrue(failed, "and the editor is told")
        XCTAssertNotNil(UIImage(data: photos[0]))
    }

    func testAllLoadedIsNoFailure() {
        XCTAssertFalse(ImageCompressor.adding([image], to: []).failed)
    }

    func testStopsAtTheLimit() {
        let existing = [Data](repeating: Data([1]), count: Limits.maxPhotos - 1)
        let (photos, failed) = ImageCompressor.adding([image, image], to: existing)
        XCTAssertEqual(photos.count, Limits.maxPhotos)
        XCTAssertFalse(failed)
    }
}
