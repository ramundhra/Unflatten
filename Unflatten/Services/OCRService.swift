import AppKit
import CoreImage
import CoreGraphics
import Foundation
import Vision

enum OCRServiceError: LocalizedError {
    case noRecognizableText

    var errorDescription: String? {
        switch self {
        case .noRecognizableText:
            "No text was found in this image."
        }
    }
}

struct OCRLineCandidate: Sendable {
    let text: String
    let confidence: Float
    let normalizedBoundingBox: CGRect
}

enum OCRService {
    static func detectRegions(
        in image: CGImage,
        pixelBuffer: ImagePixelBuffer
    ) throws -> [TextRegion] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]
        request.minimumTextHeight = 0.005

        let recognitionImage = enhancedRecognitionImageIfNeeded(image)
        let handler = VNImageRequestHandler(
            cgImage: recognitionImage,
            orientation: .up,
            options: [:]
        )
        try handler.perform([request])

        let observations = request.results ?? []
        let lines = observations.compactMap(recognizedLine)

        guard !lines.isEmpty else {
            throw OCRServiceError.noRecognizableText
        }

        return makeRegions(from: lines, pixelBuffer: pixelBuffer)
    }

    static func makeRegions(
        from lines: [OCRLineCandidate],
        pixelBuffer: ImagePixelBuffer
    ) -> [TextRegion] {
        lines.map { line in
            let imageRect = CoordinateMapper
                .visionToImage(line.normalizedBoundingBox, imageSize: pixelBuffer.size)
                .integral
            let sample = BackgroundSampler.sampleTextBackground(
                image: pixelBuffer,
                around: imageRect
            )
            let typography = TypographyEstimator.estimate(
                text: line.text,
                image: pixelBuffer,
                inside: imageRect,
                background: sample.color
            )
            let style = TextStyle.estimated(
                fontSize: typography.fontSize,
                weight: typography.weight,
                textColor: typography.textColor,
                backgroundColor: sample.color,
                outlineColor: typography.outlineColor,
                outlineWidth: typography.outlineWidth,
                letterSpacing: typography.letterSpacing
            )

            return TextRegion(
                id: UUID(),
                source: .ocr,
                originalText: line.text,
                replacementText: line.text,
                confidence: line.confidence,
                normalizedBoundingBox: line.normalizedBoundingBox,
                imageBoundingBox: imageRect,
                detectedStyle: style,
                style: style,
                backgroundUniformity: sample.uniformity,
                backgroundIsSimple: sample.isSimple,
                cleanupPadding: max(1, min(4, imageRect.height * 0.08))
            )
        }
        .filter { $0.imageBoundingBox.width >= 2 && $0.imageBoundingBox.height >= 2 }
        .sorted {
            if abs($0.imageBoundingBox.minY - $1.imageBoundingBox.minY) < 4 {
                return $0.imageBoundingBox.minX < $1.imageBoundingBox.minX
            }
            return $0.imageBoundingBox.minY < $1.imageBoundingBox.minY
        }
    }

    private static func recognizedLine(from observation: VNRecognizedTextObservation) -> OCRLineCandidate? {
        guard let candidate = observation.topCandidates(1).first else { return nil }
        let text = candidate.string
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !text.isEmpty else { return nil }

        // A Vision text observation represents a natural text line. Keep its
        // complete candidate and geometry together so the editor exposes one
        // textbox per line instead of splitting the result into words.
        return OCRLineCandidate(
            text: text,
            confidence: candidate.confidence,
            normalizedBoundingBox: observation.boundingBox
        )
    }

    /// Vision is much more reliable when tiny JPEG lettering is presented at a
    /// useful working resolution. Normalized OCR coordinates remain unchanged,
    /// so the result still maps directly onto the untouched source image.
    private static func enhancedRecognitionImageIfNeeded(_ image: CGImage) -> CGImage {
        let longestSide = CGFloat(max(image.width, image.height))
        guard longestSide > 0, longestSide < 900 else { return image }

        let scale = min(4, 900 / longestSide)
        guard scale > 1.05 else { return image }

        let input = CIImage(cgImage: image)
        let enlarged = input.applyingFilter(
            "CILanczosScaleTransform",
            parameters: [
                "inputScale": scale,
                "inputAspectRatio": 1
            ]
        )
        let clarified = enlarged
            .applyingFilter(
                "CIColorControls",
                parameters: ["inputContrast": 1.12]
            )
            .applyingFilter(
                "CISharpenLuminance",
                parameters: ["inputSharpness": 0.32]
            )
        let context = CIContext(options: [.cacheIntermediates: false])
        return context.createCGImage(clarified, from: clarified.extent.integral) ?? image
    }
}
