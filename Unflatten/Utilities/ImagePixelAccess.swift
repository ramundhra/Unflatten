import CoreGraphics
import Foundation

enum ImagePixelError: LocalizedError {
    case invalidDimensions
    case contextCreationFailed
    case imageCreationFailed

    var errorDescription: String? {
        switch self {
        case .invalidDimensions:
            "The image has invalid pixel dimensions."
        case .contextCreationFailed:
            "The image could not be converted to an editable pixel buffer."
        case .imageCreationFailed:
            "The rendered pixel buffer could not be converted back into an image."
        }
    }
}

/// An immutable-by-default, canonical 8-bit sRGB RGBA representation.
///
/// Row zero is treated as the top row throughout Unflatten. Rendering starts by
/// copying this buffer so pixels outside declared edit rectangles remain exact.
struct ImagePixelBuffer: @unchecked Sendable {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    var pixels: [UInt8]

    var size: CGSize {
        CGSize(width: width, height: height)
    }

    init(cgImage: CGImage) throws {
        guard cgImage.width > 0, cgImage.height > 0 else {
            throw ImagePixelError.invalidDimensions
        }

        width = cgImage.width
        height = cgImage.height
        bytesPerRow = width * 4
        pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue

        let didDraw = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                  ) else {
                return false
            }

            context.interpolationQuality = .none
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            context.flush()
            return true
        }

        guard didDraw else {
            throw ImagePixelError.contextCreationFailed
        }
    }

    init(width: Int, height: Int, fill color: RGBAColor) throws {
        guard width > 0, height > 0 else {
            throw ImagePixelError.invalidDimensions
        }

        self.width = width
        self.height = height
        bytesPerRow = width * 4
        pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        fill(rect: CGRect(x: 0, y: 0, width: width, height: height), color: color)
    }

    func color(x: Int, y: Int) -> RGBAColor? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        let offset = y * bytesPerRow + x * 4
        let alpha = pixels[offset + 3]

        guard alpha > 0 else {
            return RGBAColor(redByte: 0, greenByte: 0, blueByte: 0, alphaByte: 0)
        }

        let scale = 255.0 / CGFloat(alpha)
        return RGBAColor(
            redByte: UInt8(min(255, (CGFloat(pixels[offset]) * scale).rounded())),
            greenByte: UInt8(min(255, (CGFloat(pixels[offset + 1]) * scale).rounded())),
            blueByte: UInt8(min(255, (CGFloat(pixels[offset + 2]) * scale).rounded())),
            alphaByte: alpha
        )
    }

    mutating func setColor(x: Int, y: Int, color: RGBAColor) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        let offset = y * bytesPerRow + x * 4
        let alpha = CGFloat(color.alphaByte) / 255
        pixels[offset] = UInt8((CGFloat(color.redByte) * alpha).rounded())
        pixels[offset + 1] = UInt8((CGFloat(color.greenByte) * alpha).rounded())
        pixels[offset + 2] = UInt8((CGFloat(color.blueByte) * alpha).rounded())
        pixels[offset + 3] = color.alphaByte
    }

    mutating func fill(rect: CGRect, color: RGBAColor) {
        let clamped = CoordinateMapper.clampedPixelRect(rect, imageSize: size)
        guard !clamped.isNull, clamped.width > 0, clamped.height > 0 else { return }

        let minX = max(0, Int(clamped.minX))
        let maxX = min(width, Int(clamped.maxX))
        let minY = max(0, Int(clamped.minY))
        let maxY = min(height, Int(clamped.maxY))
        let alpha = CGFloat(color.alphaByte) / 255
        let rgba = [
            UInt8((CGFloat(color.redByte) * alpha).rounded()),
            UInt8((CGFloat(color.greenByte) * alpha).rounded()),
            UInt8((CGFloat(color.blueByte) * alpha).rounded()),
            color.alphaByte
        ]

        for y in minY..<maxY {
            for x in minX..<maxX {
                let offset = y * bytesPerRow + x * 4
                pixels[offset] = rgba[0]
                pixels[offset + 1] = rgba[1]
                pixels[offset + 2] = rgba[2]
                pixels[offset + 3] = rgba[3]
            }
        }
    }

    func makeCGImage() throws -> CGImage {
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGBitmapInfo.byteOrder32Big.rawValue
                        | CGImageAlphaInfo.premultipliedLast.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw ImagePixelError.imageCreationFailed
        }

        return image
    }
}
