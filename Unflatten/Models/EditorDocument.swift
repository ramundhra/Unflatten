import AppKit
import CoreGraphics
import OSLog

@MainActor
final class EditorDocument: ObservableObject {
    @Published private(set) var originalImage: CGImage?
    @Published private(set) var previewImage: CGImage?
    @Published private(set) var regions: [TextRegion] = []
    @Published var selectedRegionID: UUID?
    @Published var isShowingBefore = false
    @Published private(set) var isOCRRunning = false
    @Published private(set) var isExporting = false
    @Published private(set) var statusMessage = "Open or paste an image to begin."
    @Published var errorMessage: String?
    @Published private(set) var renderWarnings: [UUID: RegionRenderWarning] = [:]
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var editingRequestToken = UUID()
    @Published private(set) var editingRegionID: UUID?
    @Published private(set) var isAddingText = false

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.raghav.Unflatten",
        category: "EditorDocument"
    )
    private var originalPixelBuffer: ImagePixelBuffer?
    private(set) var sourceName = "image"
    private var undoStack: [[TextRegion]] = []
    private var redoStack: [[TextRegion]] = []
    private var lastCoalescingKey: String?
    private var lastChangeDate = Date.distantPast
    private var previewTask: Task<Void, Never>?
    private var ocrTask: Task<Void, Never>?
    private var renderGeneration = 0

    var hasImage: Bool {
        originalImage != nil
    }

    var displayedImage: CGImage? {
        isShowingBefore ? originalImage : (previewImage ?? originalImage)
    }

    var pixelSize: CGSize {
        guard let originalImage else { return .zero }
        return CGSize(width: originalImage.width, height: originalImage.height)
    }

    var selectedRegion: TextRegion? {
        guard let selectedRegionID else { return nil }
        return regions.first { $0.id == selectedRegionID }
    }

    func region(id: UUID) -> TextRegion? {
        regions.first { $0.id == id }
    }

    func openImage() {
        do {
            let imported = try ImageImportService.chooseImage()
            try install(imported)
        } catch ImageImportError.cancelled {
            return
        } catch {
            present(error)
        }
    }

    func importURL(_ url: URL) {
        Task {
            do {
                let imported = try await Task.detached(priority: .userInitiated) {
                    try ImageImportService.load(url: url)
                }.value
                try install(imported)
            } catch {
                present(error)
            }
        }
    }

    func pasteImage() {
        do {
            let imported = try ImageImportService.pasteImage()
            try install(imported)
        } catch {
            present(error)
        }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { provider in
            provider.hasItemConformingToTypeIdentifier("public.file-url")
                || provider.hasItemConformingToTypeIdentifier("public.image")
        }) else {
            errorMessage = ImageImportError.unsupportedType.localizedDescription
            return false
        }

        Task {
            do {
                let imported = try await ImageImportService.load(provider: provider)
                try install(imported)
            } catch {
                present(error)
            }
        }
        return true
    }

    func runOCR() {
        guard let image = originalImage,
              let buffer = originalPixelBuffer,
              !isOCRRunning else {
            return
        }

        ocrTask?.cancel()
        isAddingText = false
        isOCRRunning = true
        errorMessage = nil
        statusMessage = "Detecting text locally…"
        selectedRegionID = nil

        ocrTask = Task {
            do {
                let detected = try await Task.detached(priority: .userInitiated) {
                    try OCRService.detectRegions(in: image, pixelBuffer: buffer)
                }.value

                guard !Task.isCancelled else { return }
                regions = detected
                clearHistory()
                isOCRRunning = false
                statusMessage = "\(detected.count) text line\(detected.count == 1 ? "" : "s") detected."
                schedulePreviewRender(immediate: true)
                logger.debug("OCR completed with \(detected.count, privacy: .public) lines.")
            } catch is CancellationError {
                isOCRRunning = false
            } catch {
                regions = []
                clearHistory()
                isOCRRunning = false
                statusMessage = "OCR did not produce editable text lines."
                present(error)
                logger.error("OCR failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func select(_ id: UUID?) {
        selectedRegionID = id
    }

    func beginEditing(_ id: UUID) {
        selectedRegionID = id
        editingRegionID = id
        editingRequestToken = UUID()
    }

    func toggleAddingText() {
        guard hasImage, !isOCRRunning else { return }
        isAddingText.toggle()
        if isAddingText {
            selectedRegionID = nil
            statusMessage = "Click inside the image to place new text."
        } else {
            statusMessage = "\(regions.count) text line\(regions.count == 1 ? "" : "s") available."
        }
    }

    func cancelAddingText() {
        guard isAddingText else { return }
        isAddingText = false
        statusMessage = "\(regions.count) text line\(regions.count == 1 ? "" : "s") available."
    }

    func addText(at imagePoint: CGPoint) {
        guard isAddingText,
              let buffer = originalPixelBuffer else {
            return
        }

        let imageBounds = CGRect(origin: .zero, size: buffer.size)
        guard imageBounds.contains(imagePoint) else {
            statusMessage = "Click inside the image to place new text."
            return
        }

        let width = min(
            max(80, buffer.size.width * 0.24),
            buffer.size.width * 0.8
        )
        let height = min(
            max(24, buffer.size.height * 0.045),
            buffer.size.height * 0.2
        )
        let origin = CGPoint(
            x: min(
                max(imagePoint.x - width / 2, imageBounds.minX),
                imageBounds.maxX - width
            ),
            y: min(
                max(imagePoint.y - height / 2, imageBounds.minY),
                imageBounds.maxY - height
            )
        )
        let imageRect = CGRect(origin: origin, size: CGSize(width: width, height: height))
            .integral
        let sample = BackgroundSampler.sample(image: buffer, around: imageRect)
        let luminance = 0.2126 * sample.color.red
            + 0.7152 * sample.color.green
            + 0.0722 * sample.color.blue
        let textColor: RGBAColor = luminance > 0.5 ? .black : .white
        let style = TextStyle.estimated(
            fontSize: max(TextRenderer.minimumFontSize, imageRect.height * 0.55),
            textColor: textColor,
            backgroundColor: sample.color
        )
        let id = UUID()
        let region = TextRegion(
            id: id,
            source: .added,
            originalText: "",
            replacementText: "New Text",
            confidence: 1,
            normalizedBoundingBox: CoordinateMapper.imageToVision(
                imageRect,
                imageSize: buffer.size
            ),
            imageBoundingBox: imageRect,
            detectedStyle: style,
            style: style,
            backgroundUniformity: sample.uniformity,
            backgroundIsSimple: sample.isSimple,
            cleanupPadding: 0
        )

        recordHistory(coalescingKey: nil)
        regions.append(region)
        isAddingText = false
        isShowingBefore = false
        statusMessage = "New text added."
        beginEditing(id)
        schedulePreviewRender(immediate: true)
    }

    func moveAddedRegion(_ id: UUID, to proposedRect: CGRect) {
        guard let buffer = originalPixelBuffer,
              region(id: id)?.source == .added else {
            return
        }

        let imageBounds = CGRect(origin: .zero, size: buffer.size)
        let standardized = proposedRect.standardized
        let size = CGSize(
            width: min(max(standardized.width, 2), imageBounds.width),
            height: min(max(standardized.height, 2), imageBounds.height)
        )
        let origin = CGPoint(
            x: min(
                max(standardized.minX, imageBounds.minX),
                imageBounds.maxX - size.width
            ),
            y: min(
                max(standardized.minY, imageBounds.minY),
                imageBounds.maxY - size.height
            )
        )
        let clampedRect = CGRect(origin: origin, size: size)

        isShowingBefore = false
        updateRegion(id: id, coalescingKey: "position-\(id)") {
            $0.imageBoundingBox = clampedRect
            $0.normalizedBoundingBox = CoordinateMapper.imageToVision(
                clampedRect,
                imageSize: buffer.size
            )
        }
    }

    func endMovingAddedRegion(_ id: UUID) {
        guard region(id: id)?.source == .added else { return }
        lastCoalescingKey = nil
        statusMessage = "Text moved."
        schedulePreviewRender(immediate: true)
    }

    func updateRegion(
        id: UUID,
        coalescingKey: String? = nil,
        mutation: (inout TextRegion) -> Void
    ) {
        guard let index = regions.firstIndex(where: { $0.id == id }) else { return }
        var updated = regions[index]
        mutation(&updated)
        guard updated != regions[index] else { return }

        recordHistory(coalescingKey: coalescingKey)
        regions[index] = updated
        schedulePreviewRender()
    }

    func setReplacementText(_ text: String, for id: UUID) {
        updateRegion(id: id, coalescingKey: "replacement-\(id)") {
            $0.replacementText = text
        }
    }

    func setFontFamily(_ family: String, for id: UUID) {
        updateRegion(id: id, coalescingKey: nil) {
            $0.style.fontFamily = family
        }
    }

    func setFontSize(_ size: CGFloat, for id: UUID) {
        updateRegion(id: id, coalescingKey: "font-size-\(id)") {
            $0.style.fontSize = min(max(size, TextRenderer.minimumFontSize), 300)
        }
    }

    func setWeight(_ weight: TextWeight, for id: UUID) {
        updateRegion(id: id) {
            $0.style.weight = weight
        }
    }

    func setTextColor(_ color: RGBAColor, for id: UUID) {
        updateRegion(id: id, coalescingKey: "text-color-\(id)") {
            $0.style.textColor = color
        }
    }

    func setBackgroundColor(_ color: RGBAColor, for id: UUID) {
        updateRegion(id: id, coalescingKey: "background-color-\(id)") {
            $0.style.backgroundColor = color
            $0.style.usesManualBackground = true
        }
    }

    func setUsesManualBackground(_ usesManualBackground: Bool, for id: UUID) {
        updateRegion(id: id) {
            $0.style.usesManualBackground = usesManualBackground
        }
    }

    func setBackgroundCleanupMode(_ mode: BackgroundCleanupMode, for id: UUID) {
        updateRegion(id: id) {
            $0.style.backgroundCleanupMode = mode
        }
    }

    func setAlignment(_ alignment: TextAlignmentOption, for id: UUID) {
        updateRegion(id: id) {
            $0.style.alignment = alignment
        }
    }

    func setTextAreaSizingMode(_ mode: TextAreaSizingMode, for id: UUID) {
        updateRegion(id: id) {
            $0.style.textAreaSizingMode = mode
        }
    }

    func setCustomAreaWidthScale(_ scale: CGFloat, for id: UUID) {
        updateRegion(id: id, coalescingKey: "area-width-\(id)") {
            $0.style.customAreaWidthScale = min(
                max(scale, TextStyle.minimumCustomAreaScale),
                TextStyle.maximumCustomAreaWidthScale
            )
        }
    }

    func setCustomAreaHeightScale(_ scale: CGFloat, for id: UUID) {
        updateRegion(id: id, coalescingKey: "area-height-\(id)") {
            $0.style.customAreaHeightScale = min(
                max(scale, TextStyle.minimumCustomAreaScale),
                TextStyle.maximumCustomAreaHeightScale
            )
        }
    }

    func setShrinkToFit(_ shrinkToFit: Bool, for id: UUID) {
        updateRegion(id: id) {
            $0.style.shrinkToFit = shrinkToFit
        }
    }

    func setMathFormattingEnabled(_ isEnabled: Bool, for id: UUID) {
        updateRegion(id: id) {
            $0.style.mathFormattingEnabled = isEnabled
        }
    }

    func insertMathMarkup(_ markup: String, for id: UUID) {
        updateRegion(id: id) {
            $0.style.mathFormattingEnabled = true
            $0.replacementText += markup
        }
        beginEditing(id)
    }

    func resetSelectedRegion() {
        guard let selectedRegionID else { return }
        resetRegion(selectedRegionID)
    }

    func resetRegion(_ id: UUID) {
        if region(id: id)?.source == .added {
            deleteRegion(id)
            return
        }

        updateRegion(id: id) {
            $0.reset()
        }
    }

    func deleteRegion(_ id: UUID) {
        guard regions.contains(where: { $0.id == id }) else { return }
        recordHistory(coalescingKey: nil)
        regions.removeAll { $0.id == id }
        if selectedRegionID == id {
            selectedRegionID = nil
        }
        renderWarnings.removeValue(forKey: id)
        statusMessage = "Text removed."
        schedulePreviewRender(immediate: true)
    }

    func resetAllEdits() {
        guard regions.contains(where: \.isEdited) else { return }
        recordHistory(coalescingKey: nil)
        regions = regions.compactMap { region in
            guard region.source != .added else { return nil }
            var reset = region
            reset.reset()
            return reset
        }
        schedulePreviewRender(immediate: true)
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(regions)
        regions = previous
        isAddingText = false
        if let selectedRegionID,
           !regions.contains(where: { $0.id == selectedRegionID }) {
            self.selectedRegionID = nil
        }
        lastCoalescingKey = nil
        updateHistoryAvailability()
        schedulePreviewRender(immediate: true)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(regions)
        regions = next
        isAddingText = false
        if let selectedRegionID,
           !regions.contains(where: { $0.id == selectedRegionID }) {
            self.selectedRegionID = nil
        }
        lastCoalescingKey = nil
        updateHistoryAvailability()
        schedulePreviewRender(immediate: true)
    }

    func copyResult() {
        guard originalPixelBuffer != nil else { return }
        isExporting = true
        statusMessage = "Rendering full-resolution result…"

        Task {
            defer { isExporting = false }
            do {
                let rendered = try await renderCurrentState()
                try ExportService.copyToPasteboard(image: rendered.image)
                renderWarnings = rendered.warnings
                statusMessage = "Edited PNG copied to the clipboard."
            } catch {
                present(error)
            }
        }
    }

    func exportPNG() {
        guard originalPixelBuffer != nil else { return }
        isExporting = true
        statusMessage = "Rendering full-resolution PNG…"

        Task {
            defer { isExporting = false }
            do {
                let rendered = try await renderCurrentState()
                let destination = try ExportService.exportPNG(
                    image: rendered.image,
                    suggestedName: sourceName
                )
                renderWarnings = rendered.warnings
                statusMessage = "Exported \(destination.lastPathComponent)."
            } catch ExportError.cancelled {
                statusMessage = "Export cancelled."
            } catch {
                present(error)
            }
        }
    }

    func warning(for id: UUID) -> RegionRenderWarning? {
        renderWarnings[id]
    }

    func dismissError() {
        errorMessage = nil
    }

    private func install(_ imported: ImportedImage) throws {
        ocrTask?.cancel()
        previewTask?.cancel()

        let buffer = try ImagePixelBuffer(cgImage: imported.cgImage)
        let canonicalImage = try buffer.makeCGImage()

        originalPixelBuffer = buffer
        originalImage = canonicalImage
        previewImage = canonicalImage
        sourceName = imported.displayName.isEmpty ? "image" : imported.displayName
        regions = []
        selectedRegionID = nil
        isAddingText = false
        renderWarnings = [:]
        isShowingBefore = false
        errorMessage = nil
        clearHistory()
        statusMessage = "\(buffer.width) × \(buffer.height) pixels. Starting OCR…"
        logger.debug(
            "Loaded image at \(buffer.width, privacy: .public) by \(buffer.height, privacy: .public) pixels."
        )
        runOCR()
    }

    private func recordHistory(coalescingKey: String?) {
        let now = Date()
        let shouldCoalesce = coalescingKey != nil
            && coalescingKey == lastCoalescingKey
            && now.timeIntervalSince(lastChangeDate) < 0.8

        if !shouldCoalesce {
            undoStack.append(regions)
            if undoStack.count > 100 {
                undoStack.removeFirst(undoStack.count - 100)
            }
        }

        redoStack.removeAll()
        lastCoalescingKey = coalescingKey
        lastChangeDate = now
        updateHistoryAvailability()
    }

    private func clearHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
        lastCoalescingKey = nil
        updateHistoryAvailability()
    }

    private func updateHistoryAvailability() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func schedulePreviewRender(immediate: Bool = false) {
        previewTask?.cancel()
        guard let source = originalPixelBuffer else { return }

        if !regions.contains(where: \.isEdited) {
            previewImage = originalImage
            renderWarnings = [:]
            return
        }

        let snapshot = regions
        renderGeneration += 1
        let generation = renderGeneration

        previewTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 55_000_000)
            }
            guard !Task.isCancelled else { return }

            do {
                let rendered = try await Task.detached(priority: .userInitiated) {
                    try TextRenderer.render(source: source, regions: snapshot)
                }.value
                guard !Task.isCancelled, generation == renderGeneration else { return }
                previewImage = rendered.image
                renderWarnings = rendered.warnings
            } catch {
                guard !Task.isCancelled else { return }
                present(error)
            }
        }
    }

    private func renderCurrentState() async throws -> RenderedImage {
        guard let source = originalPixelBuffer else {
            throw ImageImportError.decodingFailed
        }
        let snapshot = regions
        return try await Task.detached(priority: .userInitiated) {
            try TextRenderer.render(source: source, regions: snapshot)
        }.value
    }

    private func present(_ error: Error) {
        guard let localized = error as? LocalizedError,
              localized.errorDescription != nil else {
            if !(error is ImageImportError) && !(error is ExportError) {
                errorMessage = "Something went wrong while processing the image."
            }
            return
        }

        errorMessage = error.localizedDescription
        statusMessage = error.localizedDescription
    }
}
