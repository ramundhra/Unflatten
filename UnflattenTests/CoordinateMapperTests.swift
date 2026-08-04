import CoreGraphics
import XCTest
@testable import Unflatten

final class CoordinateMapperTests: XCTestCase {
    func testVisionToTopLeftImageCoordinatesOnNonSquareImage() {
        let visionRect = CGRect(x: 0.25, y: 0.10, width: 0.5, height: 0.2)
        let imageRect = CoordinateMapper.visionToImage(
            visionRect,
            imageSize: CGSize(width: 1_000, height: 400)
        )

        XCTAssertEqual(imageRect.origin.x, 250, accuracy: 0.001)
        XCTAssertEqual(imageRect.origin.y, 280, accuracy: 0.001)
        XCTAssertEqual(imageRect.width, 500, accuracy: 0.001)
        XCTAssertEqual(imageRect.height, 80, accuracy: 0.001)
    }

    func testVisionAndImageCoordinatesRoundTrip() {
        let imageSize = CGSize(width: 1_600, height: 900)
        let original = CGRect(x: 123, y: 234, width: 456, height: 78)
        let vision = CoordinateMapper.imageToVision(original, imageSize: imageSize)
        let roundTrip = CoordinateMapper.visionToImage(vision, imageSize: imageSize)

        XCTAssertEqual(roundTrip.minX, original.minX, accuracy: 0.001)
        XCTAssertEqual(roundTrip.minY, original.minY, accuracy: 0.001)
        XCTAssertEqual(roundTrip.width, original.width, accuracy: 0.001)
        XCTAssertEqual(roundTrip.height, original.height, accuracy: 0.001)
    }

    func testAspectFitProducesVerticalLetterboxing() {
        let rect = CoordinateMapper.aspectFitRect(
            imageSize: CGSize(width: 400, height: 200),
            canvasSize: CGSize(width: 300, height: 300)
        )

        XCTAssertEqual(rect, CGRect(x: 0, y: 75, width: 300, height: 150))
    }

    func testImageRegionMapsIntoLetterboxedCanvas() {
        let displayed = CGRect(x: 0, y: 75, width: 300, height: 150)
        let result = CoordinateMapper.imageToCanvas(
            CGRect(x: 100, y: 50, width: 200, height: 100),
            imageSize: CGSize(width: 400, height: 200),
            displayedImageRect: displayed
        )

        XCTAssertEqual(result, CGRect(x: 75, y: 112.5, width: 150, height: 75))
    }

    func testZoomAndPanKeepImageCenteredAroundFittedRect() {
        let displayed = CoordinateMapper.displayedImageRect(
            imageSize: CGSize(width: 400, height: 200),
            canvasSize: CGSize(width: 300, height: 300),
            zoom: 2,
            pan: CGSize(width: 20, height: -10)
        )

        XCTAssertEqual(displayed, CGRect(x: -130, y: -10, width: 600, height: 300))
    }
}
