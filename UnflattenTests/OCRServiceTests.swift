import CoreGraphics
import XCTest
@testable import Unflatten

final class OCRServiceTests: XCTestCase {
    func testMultiwordOCRLineRemainsOneEditableRegion() throws {
        let canonical = try ImagePixelBuffer(width: 900, height: 180, fill: .white)
        let candidate = OCRLineCandidate(
            text: "Edit this whole line",
            confidence: 0.98,
            normalizedBoundingBox: CGRect(x: 0.06, y: 0.28, width: 0.88, height: 0.44)
        )
        let detected = OCRService.makeRegions(from: [candidate], pixelBuffer: canonical)
        let phrase = try XCTUnwrap(detected.first)

        XCTAssertEqual(phrase.originalText, "Edit this whole line")
        XCTAssertEqual(phrase.replacementText, phrase.originalText)
        XCTAssertEqual(detected.count, 1)
        XCTAssertEqual(phrase.confidence, 0.98, accuracy: 0.001)
    }
}
