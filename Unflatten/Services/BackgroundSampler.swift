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
