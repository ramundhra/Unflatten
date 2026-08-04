import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct ImportedImage: @unchecked Sendable {
    let cgImage: CGImage
    let sourceURL: URL?
    let displayName: String
}

enum ImageImportError: LocalizedError {
    case cancelled
    case unsupportedType
    case decodingFailed
    case emptyClipboard
    case droppedItemUnavailable

    var errorDescription: String? {
        switch self {
        case .cancelled:
            nil
        case .unsupportedType:
            "Choose a PNG, JPEG, or HEIC image."
        case .decodingFailed:
            "The selected image could not be decoded."
        case .emptyClipboard:
            "The clipboard does not contain a usable image."
        case .droppedItemUnavailable:
            "The dropped item could not be read as an image."
        }
    }
}

enum ImageImportService {
    @MainActor
    static func chooseImage() throws -> ImportedImage {
        let panel = NSOpenPanel()
        panel.title = "Open Screenshot"
        panel.prompt = "Open"
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else {
            throw ImageImportError.cancelled
        }

        return try load(url: url)
    }

    static func load(url: URL) throws -> ImportedImage {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let type = UTType(filenameExtension: url.pathExtension),
              type.conforms(to: .png) || type.conforms(to: .jpeg) || type.conforms(to: .heic) else {
            throw ImageImportError.unsupportedType
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = decodedImage(from: source) else {
            throw ImageImportError.decodingFailed
        }

        return ImportedImage(
            cgImage: image,
            sourceURL: url,
            displayName: url.deletingPathExtension().lastPathComponent
        )
    }

    @MainActor
    static func pasteImage() throws -> ImportedImage {
        let pasteboard = NSPasteboard.general

        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            return try load(data: data, displayName: "Pasted Image")
        }

        if let image = NSImage(pasteboard: pasteboard),
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return ImportedImage(cgImage: cgImage, sourceURL: nil, displayName: "Pasted Image")
        }

        throw ImageImportError.emptyClipboard
    }

    static func load(data: Data, displayName: String) throws -> ImportedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = decodedImage(from: source) else {
            throw ImageImportError.decodingFailed
        }

        return ImportedImage(cgImage: image, sourceURL: nil, displayName: displayName)
    }

    static func load(provider: NSItemProvider) async throws -> ImportedImage {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let data = try await dataRepresentation(
                provider: provider,
                typeIdentifier: UTType.fileURL.identifier
            )
            guard let url = URL(dataRepresentation: data, relativeTo: nil) else {
                throw ImageImportError.droppedItemUnavailable
            }
            return try load(url: url)
        }

        for type in [UTType.png, UTType.jpeg, UTType.heic, UTType.image] {
            if provider.hasItemConformingToTypeIdentifier(type.identifier) {
                let data = try await dataRepresentation(
                    provider: provider,
                    typeIdentifier: type.identifier
                )
                return try load(data: data, displayName: "Dropped Image")
            }
        }

        throw ImageImportError.unsupportedType
    }

    private static func dataRepresentation(
        provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: ImageImportError.droppedItemUnavailable)
                }
            }
        }
    }

    private static func decodedImage(from source: CGImageSource) -> CGImage? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }

        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientationValue = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1

        if orientationValue == 1 {
            return CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            )
        }

        let maximumDimension = max(width, height)
        guard maximumDimension > 0 else {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
