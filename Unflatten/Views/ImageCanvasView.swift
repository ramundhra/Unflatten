import SwiftUI

struct ImageCanvasView: View {
    private enum CanvasDragMode {
        case moveAddedText(id: UUID, startingRect: CGRect)
        case pan
    }

    @ObservedObject var document: EditorDocument
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var committedPan: CGSize = .zero
    @State private var hoveredRegionID: UUID?
    @State private var canvasDragMode: CanvasDragMode?

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = proxy.size
            let displayedRect = CoordinateMapper.displayedImageRect(
                imageSize: document.pixelSize,
                canvasSize: canvasSize,
                zoom: zoom,
                pan: pan
            )

            ZStack {
                UnflattenTheme.workspaceBackground

                if let image = document.displayedImage {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: displayedRect.width, height: displayedRect.height)
                        .position(x: displayedRect.midX, y: displayedRect.midY)
                        .overlay {
                            Rectangle()
                                .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                        }
                        .shadow(color: .black.opacity(0.24), radius: 18, y: 7)
                }

                if !document.isOCRRunning {
                    ForEach(document.regions) { region in
                        regionOverlay(region, displayedImageRect: displayedRect)
                    }
                }

                if document.isAddingText {
                    Label("Click anywhere on the image to place text", systemImage: "text.badge.plus")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.regularMaterial, in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .top
                        )
                        .padding(.top, 12)
                        .allowsHitTesting(false)
                }

                zoomControls
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(12)
            }
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        let imagePoint = CoordinateMapper.canvasToImage(
                            value.location,
                            imageSize: document.pixelSize,
                            displayedImageRect: displayedRect
                        )
                        if document.isAddingText {
                            document.addText(at: imagePoint)
                            return
                        }

                        let hitRegion = document.regions.contains { region in
                            interactiveRect(for: region)
                                .insetBy(dx: -4, dy: -4)
                                .contains(imagePoint)
                        }
                        if !hitRegion {
                            document.select(nil)
                        }
                    }
            )
            .simultaneousGesture(magnificationGesture)
            .simultaneousGesture(
                canvasDragGesture(displayedImageRect: displayedRect)
            )
        }
        .onChange(of: document.pixelSize) {
            resetViewport()
        }
    }

    @ViewBuilder
    private func regionOverlay(_ region: TextRegion, displayedImageRect: CGRect) -> some View {
        let rect = CoordinateMapper.imageToCanvas(
            interactiveRect(for: region),
            imageSize: document.pixelSize,
            displayedImageRect: displayedImageRect
        )
        let isSelected = document.selectedRegionID == region.id
        let isHovered = hoveredRegionID == region.id
        let color: Color = isSelected ? .accentColor : (isHovered ? .accentColor : .white)

        Button {
            document.select(region.id)
        } label: {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
                .overlay {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(
                            color.opacity(document.isShowingBefore ? 0.45 : 0.9),
                            lineWidth: isSelected ? 2 : (isHovered ? 1.5 : 1)
                        )
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .padding(-max(3, 8 - min(rect.width, rect.height) / 2))
        }
        .frame(width: max(rect.width, 4), height: max(rect.height, 4))
        .position(x: rect.midX, y: rect.midY)
        .shadow(
            color: isSelected ? Color.accentColor.opacity(0.28) : .clear,
            radius: 4
        )
        .allowsHitTesting(!document.isAddingText)
        .onHover { hovering in
            hoveredRegionID = hovering ? region.id : (hoveredRegionID == region.id ? nil : hoveredRegionID)
        }
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    document.beginEditing(region.id)
                }
        )
        .accessibilityLabel(
            region.source == .added
                ? "Added text: \(region.replacementText)"
                : "Text line: \(region.originalText)"
        )
        .accessibilityHint(
            region.source == .added
                ? "Drag to move this text. Double-click to edit it."
                : "Select this OCR line. Double-click to focus replacement text."
        )
        .help(
            region.source == .added
                ? "Drag to move this text"
                : region.originalText
        )
    }

    private func interactiveRect(for region: TextRegion) -> CGRect {
        guard region.isEdited else { return region.imageBoundingBox }
        return TextRenderer.drawingRect(
            for: region,
            imageSize: document.pixelSize
        )
    }

    private var zoomControls: some View {
        HStack(spacing: 3) {
            Button {
                setZoom(zoom / 1.25)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 24, height: 24)
            }
            .help("Zoom out")

            Button {
                resetViewport()
            } label: {
                Text("\(Int((zoom * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 46, height: 24)
            }
            .help("Fit image")

            Button {
                setZoom(zoom * 1.25)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 24, height: 24)
            }
            .help("Zoom in")
        }
        .buttonStyle(.plain)
        .controlSize(.small)
        .padding(6)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(UnflattenTheme.border, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.10), radius: 7, y: 3)
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoom = min(max(committedZoom * value, 0.25), 8)
                if zoom <= 1 {
                    pan = .zero
                    committedPan = .zero
                }
            }
            .onEnded { _ in
                committedZoom = zoom
            }
    }

    private func canvasDragGesture(
        displayedImageRect: CGRect
    ) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard !document.isAddingText else { return }

                let activeMode: CanvasDragMode
                if let canvasDragMode {
                    activeMode = canvasDragMode
                } else {
                    let startPoint = CoordinateMapper.canvasToImage(
                        value.startLocation,
                        imageSize: document.pixelSize,
                        displayedImageRect: displayedImageRect
                    )
                    if let region = document.regions.reversed().first(where: {
                        $0.source == .added
                            && interactiveRect(for: $0)
                                .insetBy(dx: -4, dy: -4)
                                .contains(startPoint)
                    }) {
                        activeMode = .moveAddedText(
                            id: region.id,
                            startingRect: region.imageBoundingBox
                        )
                        document.select(region.id)
                    } else {
                        activeMode = .pan
                    }
                    canvasDragMode = activeMode
                }

                switch activeMode {
                case let .moveAddedText(id, startingRect):
                    guard displayedImageRect.width > 0,
                          displayedImageRect.height > 0 else {
                        return
                    }
                    let translation = CGSize(
                        width: value.translation.width
                            * document.pixelSize.width
                            / displayedImageRect.width,
                        height: value.translation.height
                            * document.pixelSize.height
                            / displayedImageRect.height
                    )
                    document.moveAddedRegion(
                        id,
                        to: startingRect.offsetBy(
                            dx: translation.width,
                            dy: translation.height
                        )
                    )
                case .pan:
                    guard zoom > 1 else { return }
                    pan = CGSize(
                        width: committedPan.width + value.translation.width,
                        height: committedPan.height + value.translation.height
                    )
                }
            }
            .onEnded { _ in
                switch canvasDragMode {
                case let .moveAddedText(id, _):
                    document.endMovingAddedRegion(id)
                case .pan:
                    committedPan = pan
                case nil:
                    break
                }
                canvasDragMode = nil
            }
    }

    private func setZoom(_ newZoom: CGFloat) {
        zoom = min(max(newZoom, 0.25), 8)
        committedZoom = zoom
        if zoom <= 1 {
            pan = .zero
            committedPan = .zero
        }
    }

    private func resetViewport() {
        zoom = 1
        committedZoom = 1
        pan = .zero
        committedPan = .zero
    }
}
