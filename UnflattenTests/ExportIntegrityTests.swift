import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Unflatten

final class ExportIntegrityTests: XCTestCase {
    func testSyntheticEditExportsAtSourceDimensionsAndPreservesOutsidePixels() throws {
        let source = try syntheticSourceWithText()
        let style = TestSupport.style(
            fontSize: 20,
            textColor: .white,
            backgroundColor: RGBAColor(redByte: 38, greenByte: 94, blueByte: 176)
        )
        let editRect = CGRect(x: 55, y: 37, width: 90, height: 26)
        let editedRegion = TestSupport.region(
            original: "temporal",
            replacement: "longitudinal",
            rect: editRect,
            style: style
        )

        let rendered = try TextRenderer.render(source: source, regions: [editedRegion])
        let result = try ImagePixelBuffer(cgImage: rendered.image)

        XCTAssertEqual(rendered.image.width, source.width)
        XCTAssertEqual(rendered.image.height, source.height)
        XCTAssertNotEqual(result.pixels, source.pixels)

        let cleanupRect = CoordinateMapper.cleanupRect(for: editedRegion, imageSize: source.size)
        assertPixelsOutside(cleanupRect, in: result, equal: source)

        let png = try ExportService.pngData(for: rendered.image)
        let imageSource = CGImageSourceCreateWithData(png as CFData, nil)
        let decoded = imageSource.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        XCTAssertEqual(decoded?.width, source.width)
        XCTAssertEqual(decoded?.height, source.height)
    }

    func testResetRegionRecreatesCanonicalOriginal() throws {
        let source = try syntheticSourceWithText()
        let style = TestSupport.style(
            fontSize: 20,
            textColor: .white,
            backgroundColor: RGBAColor(redByte: 38, greenByte: 94, blueByte: 176)
        )
        var region = TestSupport.region(
            original: "temporal",
            replacement: "longitudinal",
            rect: CGRect(x: 55, y: 37, width: 90, height: 26),
            style: style
        )
        region.reset()

        let rendered = try TextRenderer.render(source: source, regions: [region])
        let resetBuffer = try ImagePixelBuffer(cgImage: rendered.image)

        XCTAssertEqual(resetBuffer.pixels, source.pixels)
    }

    func testComplexBackgroundRemainsUnchangedWithoutManualColor() throws {
        let source = try ImagePixelBuffer(
            width: 120,
            height: 70,
            fill: RGBAColor(redByte: 200, greenByte: 200, blueByte: 200)
        )
        let style = TestSupport.style(fontSize: 18)
        let region = TestSupport.region(
            original: "old",
            replacement: "new",
            rect: CGRect(x: 30, y: 20, width: 60, height: 24),
            style: style,
            backgroundIsSimple: false
        )

        let rendered = try TextRenderer.render(source: source, regions: [region])
        let result = try ImagePixelBuffer(cgImage: rendered.image)

        XCTAssertEqual(result.pixels, source.pixels)
        XCTAssertEqual(rendered.warnings[region.id], .complexBackground)
    }

    private func syntheticSourceWithText() throws -> ImagePixelBuffer {
        var base = try ImagePixelBuffer(
            width: 200,
            height: 100,
            fill: RGBAColor(redByte: 245, greenByte: 245, blueByte: 245)
        )
        let nodeColor = RGBAColor(redByte: 38, greenByte: 94, blueByte: 176)
        base.fill(rect: CGRect(x: 40, y: 25, width: 120, height: 50), color: nodeColor)

        let style = TestSupport.style(
            fontSize: 20,
            textColor: .white,
            backgroundColor: nodeColor
        )
        let seedRegion = TestSupport.region(
            original: "",
            replacement: "temporal",
            rect: CGRect(x: 55, y: 37, width: 90, height: 26),
            style: style
        )
        let seeded = try TextRenderer.render(source: base, regions: [seedRegion])
        return try ImagePixelBuffer(cgImage: seeded.image)
    }

    private func assertPixelsOutside(
        _ editRect: CGRect,
        in result: ImagePixelBuffer,
        equal original: ImagePixelBuffer,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(result.width, original.width, file: file, line: line)
        XCTAssertEqual(result.height, original.height, file: file, line: line)

        for y in 0..<original.height {
            for x in 0..<original.width {
                if editRect.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) {
                    continue
                }
                let offset = y * original.bytesPerRow + x * 4
                XCTAssertEqual(
                    Array(result.pixels[offset..<(offset + 4)]),
                    Array(original.pixels[offset..<(offset + 4)]),
                    "Pixel changed outside the declared edit rectangle at (\(x), \(y)).",
                    file: file,
                    line: line
                )
            }
        }
    }
}
