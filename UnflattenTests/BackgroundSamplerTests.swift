import CoreGraphics
import XCTest
@testable import Unflatten

final class BackgroundSamplerTests: XCTestCase {
    func testSolidWhiteBackground() throws {
        let image = try ImagePixelBuffer(width: 80, height: 60, fill: .white)
        let result = BackgroundSampler.sample(
            image: image,
            around: CGRect(x: 20, y: 20, width: 30, height: 12)
        )

        XCTAssertTrue(result.isSimple)
        XCTAssertGreaterThan(result.uniformity, 0.99)
        TestSupport.assertColor(result.color, approximately: .white)
    }

    func testSolidColoredBackground() throws {
        let blue = RGBAColor(redByte: 45, greenByte: 105, blueByte: 210)
        let image = try ImagePixelBuffer(width: 80, height: 60, fill: blue)
        let result = BackgroundSampler.sample(
            image: image,
            around: CGRect(x: 20, y: 20, width: 30, height: 12)
        )

        XCTAssertTrue(result.isSimple)
        TestSupport.assertColor(result.color, approximately: blue)
    }

    func testSlightNoiseRemainsAcceptable() throws {
        let base = RGBAColor(redByte: 180, greenByte: 190, blueByte: 200)
        var image = try ImagePixelBuffer(width: 80, height: 60, fill: base)

        for y in 14..<40 {
            for x in 14..<58 where (x + y).isMultiple(of: 3) {
                image.setColor(
                    x: x,
                    y: y,
                    color: RGBAColor(
                        redByte: UInt8(176 + (x % 7)),
                        greenByte: UInt8(186 + (y % 7)),
                        blueByte: UInt8(196 + ((x + y) % 7))
                    )
                )
            }
        }

        let result = BackgroundSampler.sample(
            image: image,
            around: CGRect(x: 20, y: 20, width: 30, height: 12)
        )

        XCTAssertTrue(result.isSimple)
        XCTAssertGreaterThan(result.uniformity, 0.85)
    }

    func testClearlyNonUniformBackgroundIsRejected() throws {
        var image = try ImagePixelBuffer(width: 80, height: 60, fill: .white)
        image.fill(
            rect: CGRect(x: 40, y: 0, width: 40, height: 60),
            color: RGBAColor(redByte: 15, greenByte: 40, blueByte: 180)
        )

        let result = BackgroundSampler.sample(
            image: image,
            around: CGRect(x: 30, y: 20, width: 20, height: 12),
            ringWidth: 8
        )

        XCTAssertFalse(result.isSimple)
        XCTAssertLessThan(result.uniformity, BackgroundSampler.simpleBackgroundThreshold)
    }

    func testMedianSamplingResistsSparseOutliers() throws {
        let beige = RGBAColor(redByte: 220, greenByte: 205, blueByte: 180)
        var image = try ImagePixelBuffer(width: 80, height: 60, fill: beige)
        let outliers = [(15, 15), (20, 15), (25, 15), (55, 20), (55, 25)]

        for (x, y) in outliers {
            image.setColor(x: x, y: y, color: .black)
        }

        let result = BackgroundSampler.sample(
            image: image,
            around: CGRect(x: 20, y: 20, width: 30, height: 12),
            ringWidth: 6
        )

        XCTAssertTrue(result.isSimple)
        TestSupport.assertColor(result.color, approximately: beige)
    }

    func testSamplingNearImageBoundary() throws {
        let green = RGBAColor(redByte: 50, greenByte: 160, blueByte: 95)
        let image = try ImagePixelBuffer(width: 20, height: 20, fill: green)
        let result = BackgroundSampler.sample(
            image: image,
            around: CGRect(x: 0, y: 0, width: 8, height: 8)
        )

        XCTAssertGreaterThan(result.sampleCount, 0)
        XCTAssertTrue(result.isSimple)
        TestSupport.assertColor(result.color, approximately: green)
    }

    func testTextWeightEstimationDistinguishesBoldFromRegular() throws {
        let regular = try renderedText(weight: .regular)
        let bold = try renderedText(weight: .bold)

        XCTAssertEqual(
            BackgroundSampler.estimateTextWeight(
                image: regular,
                inside: CGRect(x: 20, y: 15, width: 420, height: 70),
                background: .white
            ),
            .regular
        )
        XCTAssertEqual(
            BackgroundSampler.estimateTextWeight(
                image: bold,
                inside: CGRect(x: 20, y: 15, width: 420, height: 70),
                background: .white
            ),
            .bold
        )
    }

    private func renderedText(weight: TextWeight) throws -> ImagePixelBuffer {
        let source = try ImagePixelBuffer(width: 460, height: 100, fill: .white)
        var style = TestSupport.style(fontSize: 32, shrinkToFit: false)
        style.weight = weight
        let region = TestSupport.region(
            original: "placeholder",
            replacement: "Final Tabular Dataset",
            rect: CGRect(x: 20, y: 15, width: 420, height: 70),
            style: style
        )
        let rendered = try TextRenderer.render(source: source, regions: [region])
        return try ImagePixelBuffer(cgImage: rendered.image)
    }
}
