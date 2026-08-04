import CoreGraphics

/// Centralized geometry conversions used by OCR, overlays, and rendering.
///
/// Canonical image rectangles use source-image pixels and a top-left origin.
/// Vision rectangles are normalized and use a bottom-left origin.
/// Canvas rectangles use SwiftUI points and a top-left origin.
enum CoordinateMapper {
    static func visionToImage(_ normalizedRect: CGRect, imageSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }

        return CGRect(
            x: normalizedRect.minX * imageSize.width,
            y: (1 - normalizedRect.maxY) * imageSize.height,
            width: normalizedRect.width * imageSize.width,
            height: normalizedRect.height * imageSize.height
        )
    }

    static func imageToVision(_ imageRect: CGRect, imageSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }

        return CGRect(
            x: imageRect.minX / imageSize.width,
            y: 1 - (imageRect.maxY / imageSize.height),
            width: imageRect.width / imageSize.width,
            height: imageRect.height / imageSize.height
        )
    }

    static func aspectFitRect(imageSize: CGSize, canvasSize: CGSize) -> CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              canvasSize.width > 0,
              canvasSize.height > 0 else {
            return .zero
        }

        let scale = min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)

        return CGRect(
            x: (canvasSize.width - fittedSize.width) / 2,
            y: (canvasSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    static func displayedImageRect(
        imageSize: CGSize,
        canvasSize: CGSize,
        zoom: CGFloat,
        pan: CGSize
    ) -> CGRect {
        let fitted = aspectFitRect(imageSize: imageSize, canvasSize: canvasSize)
        let safeZoom = max(zoom, 0.05)
        let displayedSize = CGSize(width: fitted.width * safeZoom, height: fitted.height * safeZoom)

        return CGRect(
            x: fitted.midX - displayedSize.width / 2 + pan.width,
            y: fitted.midY - displayedSize.height / 2 + pan.height,
            width: displayedSize.width,
            height: displayedSize.height
        )
    }

    static func imageToCanvas(
        _ imageRect: CGRect,
        imageSize: CGSize,
        displayedImageRect: CGRect
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }

        let scaleX = displayedImageRect.width / imageSize.width
        let scaleY = displayedImageRect.height / imageSize.height

        return CGRect(
            x: displayedImageRect.minX + imageRect.minX * scaleX,
            y: displayedImageRect.minY + imageRect.minY * scaleY,
            width: imageRect.width * scaleX,
            height: imageRect.height * scaleY
        )
    }

    static func canvasToImage(
        _ canvasPoint: CGPoint,
        imageSize: CGSize,
        displayedImageRect: CGRect
    ) -> CGPoint {
        guard displayedImageRect.width > 0, displayedImageRect.height > 0 else { return .zero }

        return CGPoint(
            x: (canvasPoint.x - displayedImageRect.minX) * imageSize.width / displayedImageRect.width,
            y: (canvasPoint.y - displayedImageRect.minY) * imageSize.height / displayedImageRect.height
        )
    }

    static func clampedPixelRect(_ rect: CGRect, imageSize: CGSize) -> CGRect {
        let standardized = rect.standardized
        let bounds = CGRect(origin: .zero, size: imageSize)
        return standardized.intersection(bounds).integral
    }

    static func cleanupRect(for region: TextRegion, imageSize: CGSize) -> CGRect {
        clampedPixelRect(
            region.imageBoundingBox.insetBy(dx: -region.cleanupPadding, dy: -region.cleanupPadding),
            imageSize: imageSize
        )
    }
}
