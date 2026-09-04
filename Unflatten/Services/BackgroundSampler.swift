import CoreGraphics
import Foundation

struct BackgroundSample: Equatable, Sendable {
    let color: RGBAColor
    let uniformity: CGFloat
    let isSimple: Bool
    let sampleCount: Int
}

enum BackgroundSampler {
    static let simpleBackgroundThreshold: CGFloat = 0.68
    private static let dominantInteriorThreshold: CGFloat = 0.56
    private static let cleanupEdgeMatchThreshold: CGFloat = 0.12
    private static let cleanupInteriorMatchThreshold: CGFloat = 0.20
    private static let cleanupColorTolerance: CGFloat = 42

    /// Keeps a solid-color cleanup patch inside the detected background shape.
    /// Vision boxes can extend a few pixels beyond a cell or label, and filling
    /// that complete rectangle would paint over the surrounding image.
    static func constrainedCleanupRect(
        image: ImagePixelBuffer,
        proposedRect: CGRect,
        background: RGBAColor
    ) -> CGRect {
        let rect = CoordinateMapper.clampedPixelRect(
            proposedRect,
            imageSize: image.size
        )
        guard rect.width >= 2, rect.height >= 2 else { return rect }

        var minX = Int(rect.minX)
        var maxX = Int(rect.maxX)
        var minY = Int(rect.minY)
        var maxY = Int(rect.maxY)

        guard backgroundMatchFraction(
            image: image,
            inside: rect,
            background: background
        ) >= cleanupInteriorMatchThreshold else {
            return rect
        }

        while maxX - minX > 2,
              backgroundMatchFraction(
                image: image,
                x: minX,
                fromY: minY,
                toY: maxY,
                background: background
              ) < cleanupEdgeMatchThreshold {
            minX += 1
        }

        while maxX - minX > 2,
              backgroundMatchFraction(
                image: image,
                x: maxX - 1,
                fromY: minY,
                toY: maxY,
                background: background
              ) < cleanupEdgeMatchThreshold {
            maxX -= 1
        }

        while maxY - minY > 2,
              backgroundMatchFraction(
                image: image,
                y: minY,
                fromX: minX,
                toX: maxX,
                background: background
              ) < cleanupEdgeMatchThreshold {
            minY += 1
        }

        while maxY - minY > 2,
              backgroundMatchFraction(
                image: image,
                y: maxY - 1,
                fromX: minX,
                toX: maxX,
                background: background
              ) < cleanupEdgeMatchThreshold {
            maxY -= 1
        }

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    /// Samples the area around an OCR line, with a fallback for text that sits
    /// close to the edge of a solid cell or label. In that layout the outer
    /// ring can contain the page background even though the pixels beneath the
    /// text have one clear dominant color.
    static func sampleTextBackground(
        image: ImagePixelBuffer,
        around textRect: CGRect
    ) -> BackgroundSample {
        let surrounding = sample(image: image, around: textRect)
        guard !surrounding.isSimple else { return surrounding }

        let interior = dominantInteriorSample(image: image, inside: textRect)
        if interior.isSimple {
            return interior
        }

        // Logos and labels often place text on a flat inner band surrounded by
        // outlines or artwork. Even when neither sample meets the conservative
        // "simple" threshold, retain whichever one has the stronger dominant
        // color so texture-preserving cleanup receives the actual text-band
        // color instead of the artwork outside it.
        return interior.uniformity >= surrounding.uniformity
            ? interior
            : surrounding
    }

    static func sample(
        image: ImagePixelBuffer,
        around textRect: CGRect,
        padding: CGFloat = 2,
        ringWidth: CGFloat = 3
    ) -> BackgroundSample {
        let imageBounds = CGRect(origin: .zero, size: image.size)
        let inner = textRect
            .insetBy(dx: -max(0, padding), dy: -max(0, padding))
            .intersection(imageBounds)
            .integral
        let outer = inner
            .insetBy(dx: -max(1, ringWidth), dy: -max(1, ringWidth))
            .intersection(imageBounds)
            .integral

        var colors = colorsInRing(image: image, inner: inner, outer: outer)

        // A region touching an image boundary can have a very small outer ring.
        // Fall back to the inner perimeter without sampling the text-heavy center.
        if colors.count < 8 {
            colors.append(contentsOf: colorsOnPerimeter(image: image, rect: inner))
        }

        guard !colors.isEmpty else {
            return BackgroundSample(color: .white, uniformity: 0, isSimple: false, sampleCount: 0)
        }

        let median = medianColor(colors)
        let distances = colors
            .map { colorDistance($0, median) }
            .sorted()

        // The 75th percentile ignores a limited number of border/text outliers
        // while still rejecting gradients, textures, and split-color rings.
        let percentileIndex = min(distances.count - 1, Int(Double(distances.count - 1) * 0.75))
        let robustDistance = distances[percentileIndex]
        let uniformity = max(0, min(1, 1 - robustDistance / 70))

        return BackgroundSample(
            color: median,
            uniformity: uniformity,
            isSimple: uniformity >= simpleBackgroundThreshold,
            sampleCount: colors.count
        )
    }

    static func estimateTextColor(
        image: ImagePixelBuffer,
        inside textRect: CGRect,
        background: RGBAColor
    ) -> RGBAColor {
        let rect = CoordinateMapper.clampedPixelRect(textRect, imageSize: image.size)
        guard rect.width > 0, rect.height > 0 else {
            return contrastColor(for: background)
        }

        var candidates: [(color: RGBAColor, distance: CGFloat)] = []
        let stride = max(1, Int(min(rect.width, rect.height) / 24))

        for y in Swift.stride(from: Int(rect.minY), to: Int(rect.maxY), by: stride) {
            for x in Swift.stride(from: Int(rect.minX), to: Int(rect.maxX), by: stride) {
                guard let color = image.color(x: x, y: y) else { continue }
                candidates.append((color, colorDistance(color, background)))
            }
        }

        candidates.sort { $0.distance > $1.distance }
        let usefulCount = min(candidates.count, max(3, candidates.count / 10))
        let highContrast = candidates.prefix(usefulCount).filter { $0.distance >= 28 }.map(\.color)

        guard !highContrast.isEmpty else {
            return contrastColor(for: background)
        }

        return medianColor(highContrast)
    }

    static func estimateTextWeight(
        image: ImagePixelBuffer,
        inside textRect: CGRect,
        background: RGBAColor
    ) -> TextWeight {
        let rect = CoordinateMapper.clampedPixelRect(textRect, imageSize: image.size)
        guard rect.width >= 4, rect.height >= 4 else { return .regular }

        var foregroundCount = 0
        var foregroundBounds = CGRect.null

        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                guard let color = image.color(x: x, y: y),
                      color.alpha > 0.5,
                      colorDistance(color, background) >= 48 else {
                    continue
                }

                foregroundCount += 1
                foregroundBounds = foregroundBounds.union(
                    CGRect(x: x, y: y, width: 1, height: 1)
                )
            }
        }

        guard foregroundCount >= 12,
              !foregroundBounds.isNull,
              foregroundBounds.width >= 3,
              foregroundBounds.height >= 8 else {
            return .regular
        }

        let inkCoverage = CGFloat(foregroundCount)
            / (foregroundBounds.width * foregroundBounds.height)

        // Bold glyphs occupy a materially larger share of their tight ink
        // bounds. Keep the threshold conservative so ordinary dense words do
        // not get promoted to bold at low resolutions.
        return inkCoverage >= 0.42 ? .bold : .regular
    }

    private static func colorsInRing(
        image: ImagePixelBuffer,
        inner: CGRect,
        outer: CGRect
    ) -> [RGBAColor] {
        guard outer.width > 0, outer.height > 0 else { return [] }
        var result: [RGBAColor] = []
        result.reserveCapacity(max(8, Int(outer.width * outer.height - inner.width * inner.height)))

        for y in Int(outer.minY)..<Int(outer.maxY) {
            for x in Int(outer.minX)..<Int(outer.maxX) {
                if inner.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) {
                    continue
                }
                if let color = image.color(x: x, y: y), color.alpha > 0.01 {
                    result.append(color)
                }
            }
        }

        return result
    }

    private static func backgroundMatchFraction(
        image: ImagePixelBuffer,
        inside rect: CGRect,
        background: RGBAColor
    ) -> CGFloat {
        var matches = 0
        var samples = 0

        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                guard let color = image.color(x: x, y: y),
                      color.alpha > 0.01 else {
                    continue
                }
                samples += 1
                if colorDistance(color, background) <= cleanupColorTolerance {
                    matches += 1
                }
            }
        }

        return samples > 0 ? CGFloat(matches) / CGFloat(samples) : 0
    }

    private static func backgroundMatchFraction(
        image: ImagePixelBuffer,
        x: Int,
        fromY: Int,
        toY: Int,
        background: RGBAColor
    ) -> CGFloat {
        guard toY > fromY else { return 0 }
        var matches = 0
        var samples = 0

        for y in fromY..<toY {
            guard let color = image.color(x: x, y: y), color.alpha > 0.01 else {
                continue
            }
            samples += 1
            if colorDistance(color, background) <= cleanupColorTolerance {
                matches += 1
            }
        }

        return samples > 0 ? CGFloat(matches) / CGFloat(samples) : 0
    }

    private static func backgroundMatchFraction(
        image: ImagePixelBuffer,
        y: Int,
        fromX: Int,
        toX: Int,
        background: RGBAColor
    ) -> CGFloat {
        guard toX > fromX else { return 0 }
        var matches = 0
        var samples = 0

        for x in fromX..<toX {
            guard let color = image.color(x: x, y: y), color.alpha > 0.01 else {
                continue
            }
            samples += 1
            if colorDistance(color, background) <= cleanupColorTolerance {
                matches += 1
            }
        }

        return samples > 0 ? CGFloat(matches) / CGFloat(samples) : 0
    }

    private static func colorsOnPerimeter(
        image: ImagePixelBuffer,
        rect: CGRect
    ) -> [RGBAColor] {
        guard rect.width > 0, rect.height > 0 else { return [] }
        var result: [RGBAColor] = []
        let minX = Int(rect.minX)
        let maxX = max(minX, Int(rect.maxX) - 1)
        let minY = Int(rect.minY)
        let maxY = max(minY, Int(rect.maxY) - 1)

        for x in minX...maxX {
            if let top = image.color(x: x, y: minY) { result.append(top) }
            if maxY != minY, let bottom = image.color(x: x, y: maxY) { result.append(bottom) }
        }

        if maxY - minY > 1 {
            for y in (minY + 1)..<maxY {
                if let left = image.color(x: minX, y: y) { result.append(left) }
                if maxX != minX, let right = image.color(x: maxX, y: y) { result.append(right) }
            }
        }

        return result
    }

    private static func dominantInteriorSample(
        image: ImagePixelBuffer,
        inside textRect: CGRect
    ) -> BackgroundSample {
        let rect = CoordinateMapper.clampedPixelRect(
            textRect,
            imageSize: image.size
        )
        guard rect.width > 0, rect.height > 0 else {
            return BackgroundSample(
                color: .white,
                uniformity: 0,
                isSimple: false,
                sampleCount: 0
            )
        }

        var colors: [RGBAColor] = []
        colors.reserveCapacity(Int(rect.width * rect.height))
        var buckets: [UInt32: [RGBAColor]] = [:]

        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                guard let color = image.color(x: x, y: y),
                      color.alpha > 0.01 else {
                    continue
                }
                colors.append(color)
                buckets[quantizedKey(for: color), default: []].append(color)
            }
        }

        guard !colors.isEmpty,
              let dominantBucket = buckets.values.max(by: {
                  $0.count < $1.count
              }) else {
            return BackgroundSample(
                color: .white,
                uniformity: 0,
                isSimple: false,
                sampleCount: 0
            )
        }

        let seedColor = medianColor(dominantBucket)
        let matchingColors = colors.filter {
            colorDistance($0, seedColor) <= 30
        }
        let support = CGFloat(matchingColors.count) / CGFloat(colors.count)
        let backgroundColor = matchingColors.isEmpty
            ? seedColor
            : medianColor(matchingColors)

        return BackgroundSample(
            color: backgroundColor,
            uniformity: support,
            isSimple: support >= dominantInteriorThreshold,
            sampleCount: colors.count
        )
    }

    private static func quantizedKey(for color: RGBAColor) -> UInt32 {
        let red = UInt32(color.redByte / 16)
        let green = UInt32(color.greenByte / 16)
        let blue = UInt32(color.blueByte / 16)
        return (red << 8) | (green << 4) | blue
    }

    private static func medianColor(_ colors: [RGBAColor]) -> RGBAColor {
        func median(_ values: [UInt8]) -> UInt8 {
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }

        return RGBAColor(
            redByte: median(colors.map(\.redByte)),
            greenByte: median(colors.map(\.greenByte)),
            blueByte: median(colors.map(\.blueByte)),
            alphaByte: median(colors.map(\.alphaByte))
        )
    }

    private static func colorDistance(_ lhs: RGBAColor, _ rhs: RGBAColor) -> CGFloat {
        let red = CGFloat(lhs.redByte) - CGFloat(rhs.redByte)
        let green = CGFloat(lhs.greenByte) - CGFloat(rhs.greenByte)
        let blue = CGFloat(lhs.blueByte) - CGFloat(rhs.blueByte)
        return sqrt(red * red + green * green + blue * blue)
    }

    private static func contrastColor(for background: RGBAColor) -> RGBAColor {
        let luminance = 0.2126 * background.red + 0.7152 * background.green + 0.0722 * background.blue
        return luminance > 0.5 ? .black : .white
    }
}
