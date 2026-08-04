import CoreGraphics
import XCTest
@testable import Unflatten

final class TextRendererTests: XCTestCase {
    func testShortReplacementFitsAtOriginalSize() {
        let style = TestSupport.style(fontSize: 20)
        let result = TextRenderer.fit(
            text: "OK",
            style: style,
            in: CGSize(width: 120, height: 40)
        )

        XCTAssertTrue(result.fits)
        XCTAssertEqual(result.fontSize, 20, accuracy: 0.01)
    }

    func testLongReplacementShrinks() {
        let style = TestSupport.style(fontSize: 24)
        let result = TextRenderer.fit(
            text: "longitudinal",
            style: style,
            in: CGSize(width: 90, height: 30)
        )

        XCTAssertTrue(result.fits)
        XCTAssertLessThan(result.fontSize, 24)
        XCTAssertGreaterThanOrEqual(result.fontSize, TextRenderer.minimumFontSize)
    }

    func testLongReplacementExpandsDrawingAreaBeforeShrinking() {
        let style = TestSupport.style(
            fontSize: 24,
            textAreaSizingMode: .automatic
        )
        let region = TestSupport.region(
            original: "Final Tabular Dataset",
            replacement: "Final Tabular Representation",
            rect: CGRect(x: 100, y: 35, width: 140, height: 28),
            style: style
        )

        let drawingRect = TextRenderer.drawingRect(
            for: region,
            imageSize: CGSize(width: 500, height: 100)
        )
        let result = TextRenderer.fit(
            text: region.replacementText,
            style: style,
            in: drawingRect.insetBy(dx: 1, dy: 1).size
        )

        XCTAssertGreaterThan(drawingRect.width, region.imageBoundingBox.width)
        XCTAssertEqual(result.fontSize, style.fontSize, accuracy: 0.01)
        XCTAssertTrue(result.fits)
    }

    func testSingleLineFitUsesVisibleGlyphHeight() {
        let style = TestSupport.style(fontSize: 24)
        let result = TextRenderer.fit(
            text: "Final Tabular Dataset",
            style: style,
            in: CGSize(width: 300, height: 20)
        )

        XCTAssertTrue(result.fits)
        XCTAssertEqual(result.fontSize, 24, accuracy: 0.01)
    }

    func testIncreasingSingleLineSizeChangesRenderedFit() {
        let smaller = TextRenderer.fit(
            text: "Final Tabular Dataset",
            style: TestSupport.style(fontSize: 18),
            in: CGSize(width: 300, height: 24)
        )
        let larger = TextRenderer.fit(
            text: "Final Tabular Dataset",
            style: TestSupport.style(fontSize: 26),
            in: CGSize(width: 300, height: 24)
        )

        XCTAssertEqual(smaller.fontSize, 18, accuracy: 0.01)
        XCTAssertEqual(larger.fontSize, 26, accuracy: 0.01)
        XCTAssertGreaterThan(larger.fontSize, smaller.fontSize)
    }

    func testMinimumFontSizeReportsFailureWhenTextStillCannotFit() {
        let style = TestSupport.style(fontSize: 28)
        let result = TextRenderer.fit(
            text: String(repeating: "very-long-", count: 20),
            style: style,
            in: CGSize(width: 30, height: 8)
        )

        XCTAssertFalse(result.fits)
        XCTAssertEqual(result.fontSize, TextRenderer.minimumFontSize, accuracy: 0.01)
    }

    func testEmptyReplacementFitsWithoutChangingRequestedSize() {
        let style = TestSupport.style(fontSize: 19)
        let result = TextRenderer.fit(
            text: "",
            style: style,
            in: CGSize(width: 1, height: 1)
        )

        XCTAssertTrue(result.fits)
        XCTAssertEqual(result.fontSize, 19, accuracy: 0.01)
    }

    func testMultilineReplacementUsesAvailableHeight() {
        let style = TestSupport.style(fontSize: 18)
        let spacious = TextRenderer.fit(
            text: "Line one\nLine two",
            style: style,
            in: CGSize(width: 120, height: 60)
        )
        let compact = TextRenderer.fit(
            text: "Line one\nLine two",
            style: style,
            in: CGSize(width: 120, height: 24)
        )

        XCTAssertTrue(spacious.fits)
        XCTAssertTrue(compact.fits)
        XCTAssertLessThan(compact.fontSize, spacious.fontSize)
    }
}
