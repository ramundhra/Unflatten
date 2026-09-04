import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @ObservedObject var document: EditorDocument
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            introduction

            Divider()

            startPanel
        }
        .background(EditorialTheme.panel)
        .onDrop(
            of: [UTType.fileURL.identifier, UTType.image.identifier],
            isTargeted: $isDropTargeted
        ) { providers in
            document.handleDrop(providers: providers)
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 1.5)
                        .frame(width: 38, height: 38)
                    Text("Aa")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .foregroundStyle(.tint)
                }

                Text("UNFLATTEN")
                    .font(.caption.weight(.bold))
                    .tracking(2.2)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 18) {
                Text("Text,\neditable again.")
                    .font(.system(size: 52, weight: .semibold, design: .serif))
                    .tracking(-1.4)
                    .fixedSize(horizontal: false, vertical: true)

                Text(
                    "Replace words in screenshots, diagrams, and photographed documents without rebuilding the image from scratch."
                )
                .font(.title3)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .frame(maxWidth: 520, alignment: .leading)
            }

            Spacer()

            Label(
                "OCR and image processing stay entirely on this Mac",
                systemImage: "lock.shield"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var startPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("START A PROJECT")
                    .font(.caption2.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Text("Choose an image")
                    .font(.title2.weight(.semibold))
            }

            VStack(spacing: 12) {
                Button {
                    document.openImage()
                } label: {
                    Label("Open Image", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("o", modifiers: .command)

                Button {
                    document.pasteImage()
                } label: {
                    Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            VStack(spacing: 10) {
                Image(
                    systemName: isDropTargeted
                        ? "arrow.down.doc.fill"
                        : "photo.on.rectangle.angled"
                )
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary)

                Text(isDropTargeted ? "Release to open" : "Or drop an image here")
                    .font(.callout.weight(.semibold))

                Text("PNG · JPEG · HEIC")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 130)
            .background(
                isDropTargeted
                    ? Color.accentColor.opacity(0.08)
                    : EditorialTheme.raised
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isDropTargeted ? Color.accentColor : EditorialTheme.rule,
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 14) {
                workflowStep("01", "Detect", "Find editable text with on-device OCR")
                workflowStep("02", "Refine", "Match type, layout, and background")
                workflowStep("03", "Export", "Save a clean, full-resolution PNG")
            }
            .padding(.top, 4)

            if let errorMessage = document.errorMessage {
                ErrorBanner(message: errorMessage) {
                    document.dismissError()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(38)
        .frame(width: 410)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(EditorialTheme.raised.opacity(0.45))
    }

    private func workflowStep(
        _ number: String,
        _ title: String,
        _ detail: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(number)
                .font(.caption2.monospaced().weight(.bold))
                .foregroundStyle(.tint)
                .frame(width: 20, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
