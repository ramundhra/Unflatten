import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ExportError: LocalizedError {
    case pngEncodingFailed
    case writeFailed
    case pasteboardWriteFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .pngEncodingFailed:
            "The edited image could not be encoded as PNG."
        case .writeFailed:
            "The PNG could not be written to the selected location."
        case .pasteboardWriteFailed:
            "The edited image could not be copied to the clipboard."
        case .cancelled:
            nil
        }
    }
}

enum ExportService {
    static func pngData(for image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ExportError.pngEncodingFailed
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.pngEncodingFailed
        }

        return data as Data
    }

    @MainActor
    static func exportPNG(
        image: CGImage,
        suggestedName: String
    ) throws -> URL {
        let panel = NSSavePanel()
        panel.title = "Export Edited PNG"
        panel.prompt = "Export"
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(suggestedName)-edited.png"

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            throw ExportError.cancelled
        }

        let data = try pngData(for: image)
        do {
            try data.write(to: destinationURL, options: .atomic)
        } catch {
            throw ExportError.writeFailed
        }
        return destinationURL
    }

    @MainActor
    static func copyToPasteboard(image: CGImage) throws {
        let nsImage = NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects([nsImage]) else {
            throw ExportError.pasteboardWriteFailed
        }
    }
}
