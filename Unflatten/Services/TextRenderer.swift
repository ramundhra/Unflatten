import AppKit
import CoreGraphics
import CoreText
import Foundation

enum RegionRenderWarning: Equatable, Sendable {
    case complexBackground
    case backgroundReconstructionFailed
    case textDoesNotFit
    case invalidFont
    case regionTooSmall

    var message: String {
        switch self {
        case .complexBackground:
            "Automatic cleanup is paused because the surrounding background is not uniform. Enable a custom background color to render this edit."
        case .backgroundReconstructionFailed:
            "Photo-aware cleanup needs visible image content on at least two sides of this text line."
        case .textDoesNotFit:
            "The replacement cannot fit inside the image at the selected font size."
        case .invalidFont:
            "The selected font is unavailable, so the system font is being used."
        case .regionTooSmall:
            "This region is extremely small and may not render legibly."
        }
    }
}

struct TextFitResult: Equatable, Sendable {
    let fontSize: CGFloat
    let fits: Bool
}

struct RenderedImage: @unchecked Sendable {
    let image: CGImage
    let warnings: [UUID: RegionRenderWarning]
}

enum TextRenderer {
    static let minimumFontSize: CGFloat = 4

    static func render(
        source: ImagePixelBuffer,
        regions: [TextRegion]
    ) throws -> RenderedImage {
        var output = source
        var warnings: [UUID: RegionRenderWarning] = [:]
        var renderableRegionIDs = Set<UUID>()
        let editedRegions = regions.filter(\.isEdited)

        for region in editedRegions {
            if !region.requiresBackgroundCleanup {
                renderableRegionIDs.insert(region.id)
                continue
            }

            let cleanupRect = CoordinateMapper.cleanupRect(for: region, imageSize: output.size)

            guard cleanupRect.width >= 2, cleanupRect.height >= 2 else {
                warnings[region.id] = .regionTooSmall
                continue
            }

            guard region.effectiveBackgroundIsUsable else {
                warnings[region.id] = .complexBackground
                continue
            }

            switch region.style.backgroundCleanupMode {
            case .solidColor:
                output.fill(rect: cleanupRect, color: region.style.backgroundColor)
                renderableRegionIDs.insert(region.id)
            case .photoAware:
                if BackgroundReconstructor.reconstruct(
                    source: source,
                    output: &output,
                    inside: cleanupRect
                ) {
                    renderableRegionIDs.insert(region.id)
                } else {
                    warnings[region.id] = .backgroundReconstructionFailed
                }
            }
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        let outputWidth = output.width
        let outputHeight = output.height
        let outputBytesPerRow = output.bytesPerRow
        let outputSize = output.size

        let didDraw = output.pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: outputWidth,
                    height: outputHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: outputBytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                  ) else {
                return false
            }

            context.setShouldAntialias(true)
            context.setShouldSmoothFonts(true)
            context.interpolationQuality = .high
            context.textMatrix = .identity

            for region in editedRegions where renderableRegionIDs.contains(region.id) {
                let topLeftRect = drawingRect(for: region, imageSize: outputSize)
                guard topLeftRect.width >= 2, topLeftRect.height >= 2 else { continue }

                let drawingRect = CGRect(
                    x: topLeftRect.minX,
                    y: CGFloat(outputHeight) - topLeftRect.maxY,
                    width: topLeftRect.width,
                    height: topLeftRect.height
                )
                let result = draw(
                    region.replacementText,
                    style: region.style,
                    in: drawingRect,
                    context: context
                )

                if result.usedFallbackFont {
                    warnings[region.id] = .invalidFont
                } else if !result.fit.fits {
                    warnings[region.id] = .textDoesNotFit
                }
            }

            context.flush()
            return true
        }

        guard didDraw else {
            throw ImagePixelError.contextCreationFailed
        }

        return RenderedImage(image: try output.makeCGImage(), warnings: warnings)
    }

    /// The source-image rectangle used to draw replacement text.
    ///
    /// The original cleanup rectangle remains unchanged. Only the drawing area
    /// grows, either just enough to preserve the requested font size or by the
    /// user's custom width and height, without erasing neighboring pixels.
    static func drawingRect(
        for region: TextRegion,
        imageSize: CGSize
    ) -> CGRect {
        let originalRect = CoordinateMapper.cleanupRect(
            for: region,
            imageSize: imageSize
        )
        guard !region.replacementText.isEmpty,
              imageSize.width > 0,
              imageSize.height > 0 else {
            return originalRect
        }

        let desiredSize: CGSize
        switch region.style.textAreaSizingMode {
        case .fixed:
            return originalRect
        case .automatic:
            let requiredSize = requiredDrawingSize(
                text: region.replacementText,
                style: region.style
            )
            desiredSize = CGSize(
                width: max(originalRect.width, ceil(requiredSize.width + 2)),
                height: max(originalRect.height, ceil(requiredSize.height + 2))
            )
        case .custom:
            desiredSize = CGSize(
                width: ceil(
                    originalRect.width
                        * min(max(region.style.customAreaWidthScale, 1), 5)
                ),
                height: ceil(
                    originalRect.height
                        * min(max(region.style.customAreaHeightScale, 1), 3)
                )
            )
        }

        guard desiredSize.width > originalRect.width
                || desiredSize.height > originalRect.height else {
            return originalRect
        }

        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let width = min(desiredSize.width, imageBounds.width)
        let height = min(desiredSize.height, imageBounds.height)

        let proposedX: CGFloat
        switch region.style.alignment {
        case .left:
            proposedX = originalRect.minX
        case .center:
            proposedX = originalRect.midX - width / 2
        case .right:
            proposedX = originalRect.maxX - width
        }

        let proposedY = originalRect.midY - height / 2
        let x = min(max(proposedX, imageBounds.minX), imageBounds.maxX - width)
        let y = min(max(proposedY, imageBounds.minY), imageBounds.maxY - height)

        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func affectedRect(
        for region: TextRegion,
        imageSize: CGSize
    ) -> CGRect {
        CoordinateMapper.cleanupRect(for: region, imageSize: imageSize)
            .union(drawingRect(for: region, imageSize: imageSize))
            .intersection(CGRect(origin: .zero, size: imageSize))
    }

    static func fit(
        text: String,
        style: TextStyle,
        in size: CGSize
    ) -> TextFitResult {
        guard !text.isEmpty else {
            return TextFitResult(fontSize: style.fontSize, fits: true)
        }

        let requestedSize = max(minimumFontSize, style.fontSize)
        let requestedMeasurement = measure(
            text: text,
            family: style.fontFamily,
            weight: style.weight,
            fontSize: requestedSize,
            mathFormattingEnabled: style.mathFormattingEnabled
        )

        if measurement(requestedMeasurement, fitsIn: size) {
            return TextFitResult(fontSize: requestedSize, fits: true)
        }

        guard style.shrinkToFit else {
            return TextFitResult(fontSize: requestedSize, fits: false)
        }

        let minimumMeasurement = measure(
            text: text,
            family: style.fontFamily,
            weight: style.weight,
            fontSize: minimumFontSize,
            mathFormattingEnabled: style.mathFormattingEnabled
        )
        guard measurement(minimumMeasurement, fitsIn: size) else {
            return TextFitResult(fontSize: minimumFontSize, fits: false)
        }

        var lower = minimumFontSize
        var upper = requestedSize

        for _ in 0..<16 {
            let candidate = (lower + upper) / 2
            let candidateMeasurement = measure(
                text: text,
                family: style.fontFamily,
                weight: style.weight,
                fontSize: candidate,
                mathFormattingEnabled: style.mathFormattingEnabled
            )
            if measurement(candidateMeasurement, fitsIn: size) {
                lower = candidate
            } else {
                upper = candidate
            }
        }

        return TextFitResult(fontSize: lower, fits: true)
    }

    static func estimatedFontSize(
        for text: String,
        family: String,
        weight: TextWeight,
        matchingVisibleHeight visibleHeight: CGFloat
    ) -> CGFloat {
        guard !text.isEmpty, visibleHeight > 0 else {
            return minimumFontSize
        }

        let referenceSize: CGFloat = 100
        let reference = measure(
            text: text,
            family: family,
            weight: weight,
            fontSize: referenceSize
        )
        guard reference.totalHeight > 0 else {
            return max(minimumFontSize, visibleHeight)
        }

        return max(
            minimumFontSize,
            visibleHeight * referenceSize / reference.totalHeight
        )
    }

    private static func requiredDrawingSize(
        text: String,
        style: TextStyle
    ) -> CGSize {
        guard !text.isEmpty else { return .zero }
        let measurement = measure(
            text: text,
            family: style.fontFamily,
            weight: style.weight,
            fontSize: max(minimumFontSize, style.fontSize),
            mathFormattingEnabled: style.mathFormattingEnabled
        )
        return CGSize(
            width: measurement.widths.max() ?? 0,
            height: measurement.totalHeight
        )
    }

    private struct DrawResult {
        let fit: TextFitResult
        let usedFallbackFont: Bool
    }

    private struct TextMeasurement {
        let widths: [CGFloat]
        let lineHeight: CGFloat
        let totalHeight: CGFloat
    }

    private struct AttributedLine {
        let string: NSAttributedString
        let baseFont: CTFont
        let usedFallbackFont: Bool
    }

    private static func draw(
        _ text: String,
        style: TextStyle,
        in rect: CGRect,
        context: CGContext
    ) -> DrawResult {
        let insetRect = rect.insetBy(dx: 1, dy: 1)
        let fit = fit(text: text, style: style, in: insetRect.size)
        guard !text.isEmpty else {
            return DrawResult(fit: fit, usedFallbackFont: false)
        }

        let lines = text.components(separatedBy: .newlines)
        let attributedLines = lines.map {
            makeAttributedLine(
                text: $0,
                family: style.fontFamily,
                weight: style.weight,
                fontSize: fit.fontSize,
                textColor: style.textColor,
                mathFormattingEnabled: style.mathFormattingEnabled
            )
        }
        let coreTextLines = attributedLines.map {
            CTLineCreateWithAttributedString($0.string)
        }
        let font = attributedLines.first?.baseFont
            ?? makeFont(
                family: style.fontFamily,
                weight: style.weight,
                size: fit.fontSize
            ).font

        let glyphBounds = coreTextLines.map { visibleBounds(for: $0, font: font) }
        let lineHeight = max(
            typographicLineHeight(font: font, fontSize: fit.fontSize),
            (glyphBounds.map(\.height).max() ?? 0) + fit.fontSize * 0.08
        )
        let layoutBounds = unionBounds(
            glyphBounds,
            baselineStep: -lineHeight
        )
        let verticalOffset = insetRect.midY - layoutBounds.midY

        context.saveGState()
        context.clip(to: rect)

        for (index, line) in coreTextLines.enumerated() {
            let bounds = glyphBounds[index]
            let x: CGFloat
            switch style.alignment {
            case .left:
                x = insetRect.minX - bounds.minX
            case .center:
                x = insetRect.midX - bounds.midX
            case .right:
                x = insetRect.maxX - bounds.maxX
            }

            context.textPosition = CGPoint(
                x: x,
                y: verticalOffset - CGFloat(index) * lineHeight
            )
            CTLineDraw(line, context)
        }

        context.restoreGState()
        return DrawResult(
            fit: fit,
            usedFallbackFont: attributedLines.contains(where: \.usedFallbackFont)
        )
    }

    private static func measure(
        text: String,
        family: String,
        weight: TextWeight,
        fontSize: CGFloat,
        mathFormattingEnabled: Bool = false
    ) -> TextMeasurement {
        let lines = text.components(separatedBy: .newlines)
        let attributedLines = lines.map {
            makeAttributedLine(
                text: $0,
                family: family,
                weight: weight,
                fontSize: fontSize,
                textColor: nil,
                mathFormattingEnabled: mathFormattingEnabled
            )
        }
        let coreTextLines = attributedLines.map {
            CTLineCreateWithAttributedString($0.string)
        }
        let font = attributedLines.first?.baseFont
            ?? makeFont(family: family, weight: weight, size: fontSize).font
        let glyphBounds = coreTextLines.map { visibleBounds(for: $0, font: font) }
        let lineHeight = max(
            typographicLineHeight(font: font, fontSize: fontSize),
            (glyphBounds.map(\.height).max() ?? 0) + fontSize * 0.08
        )
        let layoutBounds = unionBounds(glyphBounds, baselineStep: -lineHeight)

        return TextMeasurement(
            widths: glyphBounds.map(\.width),
            lineHeight: lineHeight,
            totalHeight: layoutBounds.height
        )
    }

    private static func makeAttributedLine(
        text: String,
        family: String,
        weight: TextWeight,
        fontSize: CGFloat,
        textColor: RGBAColor?,
        mathFormattingEnabled: Bool
    ) -> AttributedLine {
        let baseFontResult = makeFont(
            family: family,
            weight: weight,
            size: fontSize
        )
        let segments = mathFormattingEnabled
            ? MathTextParser.parse(text)
            : [MathTextSegment(text: text, role: .normal)]
        let attributedString = NSMutableAttributedString()
        var usedFallbackFont = baseFontResult.usedFallback

        for segment in segments {
            let scale: CGFloat
            let baselineOffset: CGFloat
            switch segment.role {
            case .normal:
                scale = 1
                baselineOffset = 0
            case .subscriptText:
                scale = 0.68
                baselineOffset = -fontSize * 0.22
            case .superscriptText:
                scale = 0.68
                baselineOffset = fontSize * 0.38
            case .fractionNumerator:
                scale = 0.68
                baselineOffset = fontSize * 0.30
            case .fractionDenominator:
                scale = 0.68
                baselineOffset = -fontSize * 0.22
            }

            let segmentFontResult: (font: CTFont, usedFallback: Bool)
            if scale == 1 {
                segmentFontResult = baseFontResult
            } else {
                segmentFontResult = makeFont(
                    family: family,
                    weight: weight,
                    size: max(1, fontSize * scale)
                )
            }
            usedFallbackFont = usedFallbackFont || segmentFontResult.usedFallback

            var attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): segmentFontResult.font
            ]
            if baselineOffset != 0 {
                attributes[
                    NSAttributedString.Key(kCTBaselineOffsetAttributeName as String)
                ] = baselineOffset
            }
            if let textColor {
                attributes[
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String)
                ] = textColor.nsColor.cgColor
            }

            attributedString.append(
                NSAttributedString(string: segment.text, attributes: attributes)
            )
        }

        return AttributedLine(
            string: attributedString,
            baseFont: baseFontResult.font,
            usedFallbackFont: usedFallbackFont
        )
    }

    private static func measurement(_ measurement: TextMeasurement, fitsIn size: CGSize) -> Bool {
        let maximumWidth = measurement.widths.max() ?? 0
        return maximumWidth <= max(0, size.width)
            && measurement.totalHeight <= max(0, size.height)
    }

    private static func typographicLineHeight(font: CTFont, fontSize: CGFloat) -> CGFloat {
        CTFontGetAscent(font)
            + CTFontGetDescent(font)
            + max(CTFontGetLeading(font), fontSize * 0.08)
    }

    private static func visibleBounds(for line: CTLine, font: CTFont) -> CGRect {
        let glyphBounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        if !glyphBounds.isNull, glyphBounds.width > 0, glyphBounds.height > 0 {
            return glyphBounds
        }

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        )
        return CGRect(
            x: 0,
            y: -descent,
            width: width,
            height: max(1, ascent + descent)
        )
    }

    private static func unionBounds(
        _ bounds: [CGRect],
        baselineStep: CGFloat
    ) -> CGRect {
        bounds.enumerated().reduce(CGRect.null) { partial, entry in
            let positioned = entry.element.offsetBy(
                dx: 0,
                dy: CGFloat(entry.offset) * baselineStep
            )
            return partial.union(positioned)
        }
    }

    private static func makeFont(
        family: String,
        weight: TextWeight,
        size: CGFloat
    ) -> (font: CTFont, usedFallback: Bool) {
        let requestedFont = NSFont(name: family, size: size)
            ?? NSFontManager.shared.font(
                withFamily: family,
                traits: [],
                weight: 5,
                size: size
            )

        guard let requestedFont else {
            let fallback = weight == .bold
                ? NSFont.boldSystemFont(ofSize: size)
                : NSFont.systemFont(ofSize: size)
            return (fallback as CTFont, true)
        }

        let resolvedFont: NSFont
        if weight == .bold {
            resolvedFont = NSFontManager.shared.convert(requestedFont, toHaveTrait: .boldFontMask)
        } else {
            resolvedFont = requestedFont
        }
        return (resolvedFont as CTFont, false)
    }
}
