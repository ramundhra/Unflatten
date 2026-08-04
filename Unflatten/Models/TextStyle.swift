import AppKit
import SwiftUI

struct RGBAColor: Codable, Equatable, Hashable, Sendable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    static let black = RGBAColor(red: 0, green: 0, blue: 0, alpha: 1)
    static let white = RGBAColor(red: 1, green: 1, blue: 1, alpha: 1)

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red.clamped(to: 0...1)
        self.green = green.clamped(to: 0...1)
        self.blue = blue.clamped(to: 0...1)
        self.alpha = alpha.clamped(to: 0...1)
    }

    init(redByte: UInt8, greenByte: UInt8, blueByte: UInt8, alphaByte: UInt8 = 255) {
        self.init(
            red: CGFloat(redByte) / 255,
            green: CGFloat(greenByte) / 255,
            blue: CGFloat(blueByte) / 255,
            alpha: CGFloat(alphaByte) / 255
        )
    }

    init(nsColor: NSColor) {
        let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.init(
            red: converted.redComponent,
            green: converted.greenComponent,
            blue: converted.blueComponent,
            alpha: converted.alphaComponent
        )
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    var swiftUIColor: Color {
        Color(nsColor: nsColor)
    }

    var redByte: UInt8 { UInt8((red * 255).rounded().clamped(to: 0...255)) }
    var greenByte: UInt8 { UInt8((green * 255).rounded().clamped(to: 0...255)) }
    var blueByte: UInt8 { UInt8((blue * 255).rounded().clamped(to: 0...255)) }
    var alphaByte: UInt8 { UInt8((alpha * 255).rounded().clamped(to: 0...255)) }
}

enum TextWeight: String, Codable, CaseIterable, Identifiable, Sendable {
    case regular
    case bold

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum TextAlignmentOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case left
    case center
    case right

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum BackgroundCleanupMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case solidColor
    case photoAware

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solidColor:
            "Solid"
        case .photoAware:
            "Photo-aware"
        }
    }
}

enum TextAreaSizingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case fixed
    case automatic
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fixed:
            "Fixed"
        case .automatic:
            "Auto"
        case .custom:
            "Custom"
        }
    }
}

struct TextStyle: Codable, Equatable, Sendable {
    var fontFamily: String
    var fontSize: CGFloat
    var weight: TextWeight
    var textColor: RGBAColor
    var backgroundColor: RGBAColor
    var usesManualBackground: Bool
    var backgroundCleanupMode: BackgroundCleanupMode
    var alignment: TextAlignmentOption
    var textAreaSizingMode: TextAreaSizingMode
    var customAreaWidthScale: CGFloat
    var customAreaHeightScale: CGFloat
    var shrinkToFit: Bool
    var mathFormattingEnabled: Bool

    static func estimated(
        fontSize: CGFloat,
        weight: TextWeight = .regular,
        textColor: RGBAColor,
        backgroundColor: RGBAColor
    ) -> TextStyle {
        TextStyle(
            fontFamily: NSFont.systemFont(ofSize: max(fontSize, 4)).familyName ?? "Helvetica",
            fontSize: max(fontSize, 4),
            weight: weight,
            textColor: textColor,
            backgroundColor: backgroundColor,
            usesManualBackground: false,
            backgroundCleanupMode: .solidColor,
            alignment: .center,
            textAreaSizingMode: .automatic,
            customAreaWidthScale: 1,
            customAreaHeightScale: 1,
            shrinkToFit: true,
            mathFormattingEnabled: false
        )
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
