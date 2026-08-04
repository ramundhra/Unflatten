import CoreGraphics
import Foundation

/// Reconstructs a removed text area from pixels immediately surrounding it.
///
/// This is an entirely local, deterministic fallback for photographed paper,
/// gradients, and lightly textured surfaces. It deliberately samples only
/// outside the cleanup rectangle so remnants of the original glyphs are not
/// copied back into the result.
enum BackgroundReconstructor {
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
}
