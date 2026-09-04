import CoreGraphics
import Foundation

enum TextRegionSource: String, Codable, Sendable {
    case ocr
    case added
}

struct TextRegion: Identifiable, Equatable, Sendable {
    let id: UUID
    let source: TextRegionSource
    let originalText: String
    var replacementText: String
    let confidence: Float

    /// Vision's lower-left-origin normalized rectangle.
    var normalizedBoundingBox: CGRect

    /// Canonical editor geometry: source-image pixels with a top-left origin.
    var imageBoundingBox: CGRect

    let detectedStyle: TextStyle
    var style: TextStyle
    let backgroundUniformity: CGFloat
    let backgroundIsSimple: Bool
    var cleanupPadding: CGFloat

    var isEdited: Bool {
        source == .added
            || replacementText != originalText
            || style != detectedStyle
    }

    var requiresBackgroundCleanup: Bool {
        source == .ocr
    }

    var effectiveBackgroundIsUsable: Bool {
        switch style.backgroundCleanupMode {
        case .preserveTexture:
            backgroundIsSimple
        case .solidColor:
            backgroundIsSimple || style.usesManualBackground
        case .photoAware:
            true
        }
    }

    mutating func reset() {
        replacementText = originalText
        style = detectedStyle
        cleanupPadding = 2
    }
}
