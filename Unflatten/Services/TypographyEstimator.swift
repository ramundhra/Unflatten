import CoreGraphics
import CoreText
import Foundation
import simd

struct TypographyEstimate: Sendable {
    let fontFamily: String
    let fontSize: CGFloat
    let weight: TextWeight
    let textColor: RGBAColor
    let outlineColor: RGBAColor
    let outlineWidth: CGFloat
    let letterSpacing: CGFloat
}

/// Estimates a practical editable style by comparing the source glyph mask
/// with a curated set of fonts already installed on the Mac. This is not font
/// identification: it chooses the locally available face whose rendered shape
/// most closely resembles the pixels in the image.
enum TypographyEstimator {
    private struct SourceMask {
        let values: [CGFloat]
        let width: Int
        let height: Int
        let normalizedInkBounds: CGRect
        let sourceInkBounds: CGRect
        let foregroundThreshold: CGFloat
    }

    private struct Appearance {
        let textColor: RGBAColor
        let outlineColor: RGBAColor
        let outlineWidth: CGFloat
    }

    private struct FontMatch {
        let family: String
        let weight: TextWeight
        let score: CGFloat
    }

    private static let candidateFamilies = [
        "Helvetica Neue",
        "Arial",
        "Arial Narrow",
        "Avenir Next",
        "Avenir Next Condensed",
        "Futura",
        "Gill Sans",
        "Optima",
        "Verdana",
        "Trebuchet MS",
        "DIN Alternate",
        "DIN Condensed",
        "Impact",
        "Rockwell",
        "American Typewriter",
        "Copperplate",
        "Baskerville",
        "Georgia",
        "Times New Roman",
        "Hoefler Text",
        "Didot",
        "Palatino",
        "Charter",
        "Iowan Old Style",
        "Courier New",
        "Menlo"
    ]

    static func estimate(
        text: String,
        image: ImagePixelBuffer,
        inside requestedRect: CGRect,
        background: RGBAColor
    ) -> TypographyEstimate {
        let rect = CoordinateMapper.clampedPixelRect(
            requestedRect,
            imageSize: image.size
        )
        let initialWeight = BackgroundSampler.estimateTextWeight(
            image: image,
            inside: rect,
            background: background
        )
        let sourceMask = makeSourceMask(
            image: image,
            inside: rect,
            background: background
        )
        let appearance = estimateAppearance(
            image: image,
            inside: rect,
            background: background,
            foregroundThreshold: sourceMask?.foregroundThreshold ?? 28,
            inkHeight: sourceMask?.sourceInkBounds.height ?? rect.height
        )
        let fallbackFamily = systemFontFamily()
        let match = sourceMask.flatMap {
            bestFontMatch(text: text, source: $0, preferredWeight: initialWeight)
        }
        let family = match?.family ?? fallbackFamily
        let weight = match?.weight ?? initialWeight
        let visibleHeight = max(
            1,
            (sourceMask?.sourceInkBounds.height ?? rect.height * 0.9)
                - appearance.outlineWidth * 2
        )
        let fontSize = TextRenderer.estimatedFontSize(
            for: text,
            family: family,
            weight: weight,
            matchingVisibleHeight: visibleHeight
        )
        let naturalWidth = visibleTextWidth(
            text: text,
            family: family,
            weight: weight,
            fontSize: fontSize
        )
        let targetWidth = max(1, sourceMask?.sourceInkBounds.width ?? rect.width)
        let characterGaps = max(1, text.count - 1)
        let inferredSpacing = (targetWidth - naturalWidth) / CGFloat(characterGaps)
        let letterSpacing = min(
            max(inferredSpacing, -fontSize * 0.08),
            fontSize * 0.22
        )

        return TypographyEstimate(
            fontFamily: family,
            fontSize: fontSize,
            weight: weight,
            textColor: appearance.textColor,
            outlineColor: appearance.outlineColor,
            outlineWidth: appearance.outlineWidth,
            letterSpacing: letterSpacing
        )
    }

    private static func makeSourceMask(
        image: ImagePixelBuffer,
        inside rect: CGRect,
        background: RGBAColor
    ) -> SourceMask? {
        guard rect.width >= 3, rect.height >= 3 else { return nil }

        var distances: [CGFloat] = []
        distances.reserveCapacity(Int(rect.width * rect.height))
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                guard let color = image.color(x: x, y: y), color.alpha > 0.01 else {
                    continue
                }
                distances.append(colorDistance(color, background))
            }
        }
        guard distances.count >= 9 else { return nil }

        distances.sort()
        let backgroundIndex = min(
            distances.count - 1,
            Int(CGFloat(distances.count - 1) * 0.45)
        )
        let backgroundVariation = distances[backgroundIndex]
        let threshold = min(58, max(16, backgroundVariation + 12))

        var sourceInkBounds = CGRect.null
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                guard let color = image.color(x: x, y: y),
                      colorDistance(color, background) >= threshold else {
                    continue
                }
                sourceInkBounds = sourceInkBounds.union(
                    CGRect(x: x, y: y, width: 1, height: 1)
                )
            }
        }
        guard !sourceInkBounds.isNull,
              sourceInkBounds.width >= 2,
              sourceInkBounds.height >= 2 else {
            return nil
        }

        let normalizedHeight = 48
        let aspectRatio = rect.width / max(1, rect.height)
        let normalizedWidth = min(
            240,
            max(48, Int((CGFloat(normalizedHeight) * aspectRatio).rounded()))
        )
        var values = [CGFloat](repeating: 0, count: normalizedWidth * normalizedHeight)
        var normalizedInkBounds = CGRect.null

        for targetY in 0..<normalizedHeight {
            for targetX in 0..<normalizedWidth {
                let sourceX = min(
                    Int(rect.maxX) - 1,
                    Int(
                        rect.minX
                            + (CGFloat(targetX) + 0.5)
                            / CGFloat(normalizedWidth) * rect.width
                    )
                )
                let sourceY = min(
                    Int(rect.maxY) - 1,
                    Int(
                        rect.minY
                            + (CGFloat(targetY) + 0.5)
                            / CGFloat(normalizedHeight) * rect.height
                    )
                )
                guard let color = image.color(x: sourceX, y: sourceY) else { continue }
                let distance = colorDistance(color, background)
                let value = min(1, max(0, (distance - threshold) / 22))
                values[targetY * normalizedWidth + targetX] = value
                if value >= 0.18 {
                    normalizedInkBounds = normalizedInkBounds.union(
                        CGRect(x: targetX, y: targetY, width: 1, height: 1)
                    )
                }
            }
        }

        guard !normalizedInkBounds.isNull else { return nil }
        return SourceMask(
            values: values,
            width: normalizedWidth,
            height: normalizedHeight,
            normalizedInkBounds: normalizedInkBounds,
            sourceInkBounds: sourceInkBounds,
            foregroundThreshold: threshold
        )
    }

    private static func bestFontMatch(
        text: String,
        source: SourceMask,
        preferredWeight: TextWeight
    ) -> FontMatch? {
        guard text.count >= 2 else { return nil }
        let installedFamilies = Set(
            CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        )
        let systemFamily = systemFontFamily()
        let families = ([systemFamily] + candidateFamilies)
            .reduce(into: [String]()) { result, family in
                guard installedFamilies.contains(family), !result.contains(family) else {
                    return
                }
                result.append(family)
            }
        let alternateWeight: TextWeight = preferredWeight == .bold ? .regular : .bold
        let weights = [preferredWeight, alternateWeight]
        var best: FontMatch?

        for family in families {
            for weight in weights {
                guard let candidate = rasterizedMask(
                    text: text,
                    family: family,
                    weight: weight,
                    width: source.width,
                    height: source.height,
                    matching: source.normalizedInkBounds
                ) else {
                    continue
                }
                let score = min(
                    maskScore(source.values, candidate, width: source.width, height: source.height),
                    maskScore(
                        source.values,
                        verticallyFlipped(candidate, width: source.width, height: source.height),
                        width: source.width,
                        height: source.height
                    )
                )
                if best == nil || score < best!.score {
                    best = FontMatch(family: family, weight: weight, score: score)
                }
            }
        }

        return best
    }

    private static func rasterizedMask(
        text: String,
        family: String,
        weight: TextWeight,
        width: Int,
        height: Int,
        matching targetBounds: CGRect
    ) -> [CGFloat]? {
        guard let referenceFont = makeFont(family: family, weight: weight, size: 100) else {
            return nil
        }
        let referenceLine = makeLine(text: text, font: referenceFont)
        let referenceBounds = CTLineGetBoundsWithOptions(referenceLine, [.useGlyphPathBounds])
        guard referenceBounds.height > 0 else { return nil }

        let fontSize = max(2, 100 * targetBounds.height / referenceBounds.height)
        guard let font = makeFont(family: family, weight: weight, size: fontSize) else {
            return nil
        }
        let line = makeLine(text: text, font: font)
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height)
        let created = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let address = rawBuffer.baseAddress,
                  let context = CGContext(
                    data: address,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else {
                return false
            }
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setShouldAntialias(true)
            context.setShouldSmoothFonts(true)
            context.textMatrix = .identity
            context.textPosition = CGPoint(
                x: targetBounds.midX - bounds.midX,
                y: CGFloat(height) - targetBounds.midY - bounds.midY
            )
            CTLineDraw(line, context)
            context.flush()
            return true
        }
        guard created else { return nil }
        return pixels.map { CGFloat($0) / 255 }
    }

    private static func makeLine(text: String, font: CTFont) -> CTLine {
        let string = NSAttributedString(
            string: text,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
                    gray: 1,
                    alpha: 1
                )
            ]
        )
        return CTLineCreateWithAttributedString(string)
    }

    private static func maskScore(
        _ source: [CGFloat],
        _ candidate: [CGFloat],
        width: Int,
        height: Int
    ) -> CGFloat {
        guard source.count == candidate.count, !source.isEmpty else { return .greatestFiniteMagnitude }
        var intersection: CGFloat = 0
        var union: CGFloat = 0
        var sourceCoverage: CGFloat = 0
        var candidateCoverage: CGFloat = 0

        for index in source.indices {
            intersection += min(source[index], candidate[index])
            union += max(source[index], candidate[index])
            sourceCoverage += source[index]
            candidateCoverage += candidate[index]
        }

        let overlapLoss = 1 - intersection / max(1, union)
        let coverageLoss = abs(log((candidateCoverage + 1) / (sourceCoverage + 1)))
        return overlapLoss + coverageLoss * 0.16
    }

    private static func verticallyFlipped(
        _ values: [CGFloat],
        width: Int,
        height: Int
    ) -> [CGFloat] {
        var flipped = values
        for y in 0..<height {
            let sourceStart = y * width
            let destinationStart = (height - y - 1) * width
            flipped.replaceSubrange(
                destinationStart..<(destinationStart + width),
                with: values[sourceStart..<(sourceStart + width)]
            )
        }
        return flipped
    }

    private static func estimateAppearance(
        image: ImagePixelBuffer,
        inside rect: CGRect,
        background: RGBAColor,
        foregroundThreshold: CGFloat,
        inkHeight: CGFloat
    ) -> Appearance {
        var buckets: [UInt32: [RGBAColor]] = [:]
        let samplingStride = max(1, Int(max(rect.width, rect.height) / 160))

        for y in Swift.stride(from: Int(rect.minY), to: Int(rect.maxY), by: samplingStride) {
            for x in Swift.stride(from: Int(rect.minX), to: Int(rect.maxX), by: samplingStride) {
                guard let color = image.color(x: x, y: y),
                      color.alpha > 0.01,
                      colorDistance(color, background) >= foregroundThreshold else {
                    continue
                }
                buckets[quantizedKey(for: color), default: []].append(color)
            }
        }

        let clusters = buckets.values
            .sorted { $0.count > $1.count }
            .prefix(6)
            .map { colors in
                (color: medianColor(colors), count: colors.count)
            }
            .sorted {
                colorDistance($0.color, background) > colorDistance($1.color, background)
            }
        guard let fillCluster = clusters.first else {
            let fallback = contrastColor(for: background)
            return Appearance(textColor: fallback, outlineColor: fallback, outlineWidth: 0)
        }

        let total = max(1, clusters.reduce(0) { $0 + $1.count })
        let possibleOutline = clusters.dropFirst().first {
            CGFloat($0.count) / CGFloat(total) >= 0.14
                && colorDistance($0.color, fillCluster.color) >= 34
                && distanceToColorSegment(
                    $0.color,
                    from: background,
                    to: fillCluster.color
                ) >= 14
        }

        guard let outlineCluster = possibleOutline else {
            return Appearance(
                textColor: fillCluster.color,
                outlineColor: fillCluster.color,
                outlineWidth: 0
            )
        }

        return Appearance(
            textColor: fillCluster.color,
            outlineColor: outlineCluster.color,
            outlineWidth: min(4, max(0.5, inkHeight * 0.055))
        )
    }

    private static func visibleTextWidth(
        text: String,
        family: String,
        weight: TextWeight,
        fontSize: CGFloat
    ) -> CGFloat {
        guard let font = makeFont(family: family, weight: weight, size: fontSize) else {
            return 0
        }
        let bounds = CTLineGetBoundsWithOptions(
            makeLine(text: text, font: font),
            [.useGlyphPathBounds]
        )
        return max(0, bounds.width)
    }

    private static func makeFont(
        family: String,
        weight: TextWeight,
        size: CGFloat
    ) -> CTFont? {
        let requested = CTFontCreateWithName(family as CFString, size, nil)
        guard weight == .bold else { return requested }
        return CTFontCreateCopyWithSymbolicTraits(
            requested,
            size,
            nil,
            .traitBold,
            .traitBold
        ) ?? requested
    }

    private static func systemFontFamily() -> String {
        guard let font = CTFontCreateUIFontForLanguage(.system, 12, nil) else {
            return "Helvetica"
        }
        return CTFontCopyFamilyName(font) as String
    }

    private static func quantizedKey(for color: RGBAColor) -> UInt32 {
        let red = UInt32(color.redByte / 32)
        let green = UInt32(color.greenByte / 32)
        let blue = UInt32(color.blueByte / 32)
        return (red << 6) | (green << 3) | blue
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

    private static func distanceToColorSegment(
        _ color: RGBAColor,
        from start: RGBAColor,
        to end: RGBAColor
    ) -> CGFloat {
        let point = SIMD3<Double>(
            Double(color.red),
            Double(color.green),
            Double(color.blue)
        )
        let startVector = SIMD3<Double>(
            Double(start.red),
            Double(start.green),
            Double(start.blue)
        )
        let endVector = SIMD3<Double>(
            Double(end.red),
            Double(end.green),
            Double(end.blue)
        )
        let segment = endVector - startVector
        let lengthSquared = max(0.000_001, simd_dot(segment, segment))
        let position = min(1, max(0, simd_dot(point - startVector, segment) / lengthSquared))
        let projected = startVector + segment * position
        let difference = point - projected
        return CGFloat(sqrt(simd_dot(difference, difference)) * 255)
    }

    private static func contrastColor(for background: RGBAColor) -> RGBAColor {
        let luminance = 0.2126 * background.red
            + 0.7152 * background.green
            + 0.0722 * background.blue
        return luminance > 0.5 ? .black : .white
    }
}
