import CoreGraphics
import XCTest
@testable import Unflatten

enum TestSupport {
    static func style(
        fontSize: CGFloat = 18,
        textColor: RGBAColor = .black,
        backgroundColor: RGBAColor = .white,
        textAreaSizingMode: TextAreaSizingMode = .fixed,
        shrinkToFit: Bool = true
    ) -> TextStyle {
        TextStyle(
            fontFamily: "Helvetica",
            fontSize: fontSize,
            weight: .regular,
            textColor: textColor,
            outlineColor: .black,
            outlineWidth: 0,
            letterSpacing: 0,
            backgroundColor: backgroundColor,
            usesManualBackground: false,
            backgroundCleanupMode: .solidColor,
            alignment: .center,
            textAreaSizingMode: textAreaSizingMode,
            customAreaWidthScale: 1,
            customAreaHeightScale: 1,
            shrinkToFit: shrinkToFit,
            mathFormattingEnabled: false
        )
    }

    static func region(
        original: String,
        replacement: String,
        rect: CGRect,
        style: TextStyle,
        backgroundIsSimple: Bool = true
    ) -> TextRegion {
        TextRegion(
            id: UUID(),
            source: .ocr,
            originalText: original,
            replacementText: replacement,
            confidence: 0.99,
            normalizedBoundingBox: CoordinateMapper.imageToVision(
                rect,
                imageSize: CGSize(width: 200, height: 100)
            ),
            imageBoundingBox: rect,
            detectedStyle: style,
            style: style,
            backgroundUniformity: backgroundIsSimple ? 1 : 0.1,
            backgroundIsSimple: backgroundIsSimple,
            cleanupPadding: 2
        )
    }

    static func assertColor(
        _ color: RGBAColor,
        approximately expected: RGBAColor,
        tolerance: UInt8 = 2,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertLessThanOrEqual(
            abs(Int(color.redByte) - Int(expected.redByte)),
            Int(tolerance),
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            abs(Int(color.greenByte) - Int(expected.greenByte)),
            Int(tolerance),
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            abs(Int(color.blueByte) - Int(expected.blueByte)),
            Int(tolerance),
            file: file,
            line: line
        )
    }
}
