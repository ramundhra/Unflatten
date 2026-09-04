import CoreGraphics
import Foundation

/// Reconstructs a removed text area from pixels immediately surrounding it.
///
/// This is an entirely local, deterministic fallback for photographed paper,
/// gradients, and lightly textured surfaces. It deliberately samples only
/// outside the cleanup rectangle so remnants of the original glyphs are not
/// copied back into the result.
enum BackgroundReconstructor {
    /// Removes only pixels that look like foreground lettering and replaces
    /// them with nearby pixels from the same background. Unlike a rectangular
    /// fill, this retains JPEG grain, paper texture, and surrounding artwork.
    static func removeForeground(
        source: ImagePixelBuffer,
        output: inout ImagePixelBuffer,
        inside requestedRect: CGRect,
        background: RGBAColor
    ) -> Bool {
        let rect = CoordinateMapper.clampedPixelRect(
            requestedRect,
            imageSize: source.size
        )
        guard rect.width >= 2, rect.height >= 2 else { return false }

        let minX = Int(rect.minX)
        let maxX = Int(rect.maxX)
        let minY = Int(rect.minY)
        let maxY = Int(rect.maxY)
        let width = maxX - minX
        let height = maxY - minY
        var distances = [CGFloat](repeating: 0, count: width * height)

        for localY in 0..<height {
            for localX in 0..<width {
                guard let color = source.color(x: minX + localX, y: minY + localY) else {
                    continue
                }
                distances[localY * width + localX] = colorDistance(color, background)
            }
        }

        let sortedDistances = distances.sorted()
        let backgroundIndex = min(
            sortedDistances.count - 1,
            Int(CGFloat(sortedDistances.count - 1) * 0.45)
        )
        let backgroundVariation = sortedDistances[backgroundIndex]
        let threshold = min(58, max(16, backgroundVariation + 12))
        var mask = distances.map { $0 >= threshold }
        let initialForegroundCount = mask.lazy.filter { $0 }.count

        guard initialForegroundCount > 0,
              CGFloat(initialForegroundCount) / CGFloat(mask.count) < 0.72 else {
            return false
        }

        // Include antialiased fringes around the detected letter pixels. One
        // source pixel is enough for small JPEGs; larger text gets two.
        let dilationRadius = min(width, height) >= 28 ? 2 : 1
        let originalMask = mask
        for localY in 0..<height {
            for localX in 0..<width where originalMask[localY * width + localX] {
                for offsetY in -dilationRadius...dilationRadius {
                    for offsetX in -dilationRadius...dilationRadius {
                        let x = localX + offsetX
                        let y = localY + offsetY
                        guard x >= 0, x < width, y >= 0, y < height else { continue }
                        mask[y * width + x] = true
                    }
                }
            }
        }

        let maximumSearchRadius = min(18, max(5, min(width, height)))
        for localY in 0..<height {
            for localX in 0..<width where mask[localY * width + localX] {
                let imageX = minX + localX
                let imageY = minY + localY
                let replacement = nearbyBackgroundColor(
                    source: source,
                    x: imageX,
                    y: imageY,
                    mask: mask,
                    maskRect: rect,
                    maskWidth: width,
                    background: background,
                    tolerance: threshold + 10,
                    maximumRadius: maximumSearchRadius
                ) ?? background
                output.setColor(x: imageX, y: imageY, color: replacement)
            }
        }

        return true
    }

    static func reconstruct(
        source: ImagePixelBuffer,
        output: inout ImagePixelBuffer,
        inside requestedRect: CGRect
    ) -> Bool {
        let rect = CoordinateMapper.clampedPixelRect(
            requestedRect,
            imageSize: source.size
        )
        guard rect.width >= 2, rect.height >= 2 else { return false }

        let minX = Int(rect.minX)
        let maxX = Int(rect.maxX)
        let minY = Int(rect.minY)
        let maxY = Int(rect.maxY)
        let hasTop = minY > 0
        let hasBottom = maxY < source.height
        let hasLeft = minX > 0
        let hasRight = maxX < source.width
        let availableEdgeCount = [hasTop, hasBottom, hasLeft, hasRight]
            .filter { $0 }
            .count

        // One edge alone cannot describe a photographic gradient reliably.
        guard availableEdgeCount >= 2 else { return false }

        for y in minY..<maxY {
            for x in minX..<maxX {
                var red: CGFloat = 0
                var green: CGFloat = 0
                var blue: CGFloat = 0
                var alpha: CGFloat = 0
                var totalWeight: CGFloat = 0

                func add(_ color: RGBAColor?, distance: CGFloat) {
                    guard let color else { return }
                    let weight = 1 / max(1, distance)
                    red += color.red * weight
                    green += color.green * weight
                    blue += color.blue * weight
                    alpha += color.alpha * weight
                    totalWeight += weight
                }

                if hasTop {
                    add(
                        horizontalSample(source: source, x: x, y: minY - 1),
                        distance: CGFloat(y - minY + 1)
                    )
                }
                if hasBottom {
                    add(
                        horizontalSample(source: source, x: x, y: maxY),
                        distance: CGFloat(maxY - y)
                    )
                }
                if hasLeft {
                    add(
                        verticalSample(source: source, x: minX - 1, y: y),
                        distance: CGFloat(x - minX + 1)
                    )
                }
                if hasRight {
                    add(
                        verticalSample(source: source, x: maxX, y: y),
                        distance: CGFloat(maxX - x)
                    )
                }

                guard totalWeight > 0 else { return false }
                output.setColor(
                    x: x,
                    y: y,
                    color: RGBAColor(
                        red: red / totalWeight,
                        green: green / totalWeight,
                        blue: blue / totalWeight,
                        alpha: alpha / totalWeight
                    )
                )
            }
        }

        return true
    }

    private static func horizontalSample(
        source: ImagePixelBuffer,
        x: Int,
        y: Int
    ) -> RGBAColor? {
        average(
            source: source,
            coordinates: [
                (x - 1, y),
                (x, y),
                (x + 1, y)
            ]
        )
    }

    private static func verticalSample(
        source: ImagePixelBuffer,
        x: Int,
        y: Int
    ) -> RGBAColor? {
        average(
            source: source,
            coordinates: [
                (x, y - 1),
                (x, y),
                (x, y + 1)
            ]
        )
    }

    private static func average(
        source: ImagePixelBuffer,
        coordinates: [(Int, Int)]
    ) -> RGBAColor? {
        let colors = coordinates.compactMap { coordinate in
            source.color(x: coordinate.0, y: coordinate.1)
        }
        guard !colors.isEmpty else { return nil }

        let count = CGFloat(colors.count)
        return RGBAColor(
            red: colors.reduce(0) { $0 + $1.red } / count,
            green: colors.reduce(0) { $0 + $1.green } / count,
            blue: colors.reduce(0) { $0 + $1.blue } / count,
            alpha: colors.reduce(0) { $0 + $1.alpha } / count
        )
    }

    private static func nearbyBackgroundColor(
        source: ImagePixelBuffer,
        x: Int,
        y: Int,
        mask: [Bool],
        maskRect: CGRect,
        maskWidth: Int,
        background: RGBAColor,
        tolerance: CGFloat,
        maximumRadius: Int
    ) -> RGBAColor? {
        let directions = [
            (-1, 0), (1, 0), (0, -1), (0, 1),
            (-1, -1), (1, -1), (-1, 1), (1, 1)
        ]
        var weightedColors: [(RGBAColor, CGFloat)] = []

        for radius in 1...maximumRadius {
            for direction in directions {
                let sampleX = x + direction.0 * radius
                let sampleY = y + direction.1 * radius
                guard let color = source.color(x: sampleX, y: sampleY),
                      colorDistance(color, background) <= tolerance else {
                    continue
                }

                if maskRect.contains(
                    CGPoint(x: CGFloat(sampleX) + 0.5, y: CGFloat(sampleY) + 0.5)
                ) {
                    let localX = sampleX - Int(maskRect.minX)
                    let localY = sampleY - Int(maskRect.minY)
                    let index = localY * maskWidth + localX
                    guard mask.indices.contains(index), !mask[index] else { continue }
                }

                weightedColors.append((color, 1 / CGFloat(radius)))
            }

            if weightedColors.count >= 4 {
                break
            }
        }

        guard !weightedColors.isEmpty else { return nil }
        let totalWeight = weightedColors.reduce(0) { $0 + $1.1 }
        return RGBAColor(
            red: weightedColors.reduce(0) { $0 + $1.0.red * $1.1 } / totalWeight,
            green: weightedColors.reduce(0) { $0 + $1.0.green * $1.1 } / totalWeight,
            blue: weightedColors.reduce(0) { $0 + $1.0.blue * $1.1 } / totalWeight,
            alpha: weightedColors.reduce(0) { $0 + $1.0.alpha * $1.1 } / totalWeight
        )
    }

    private static func colorDistance(_ lhs: RGBAColor, _ rhs: RGBAColor) -> CGFloat {
        let red = CGFloat(lhs.redByte) - CGFloat(rhs.redByte)
        let green = CGFloat(lhs.greenByte) - CGFloat(rhs.greenByte)
        let blue = CGFloat(lhs.blueByte) - CGFloat(rhs.blueByte)
        return sqrt(red * red + green * green + blue * blue)
    }
}
