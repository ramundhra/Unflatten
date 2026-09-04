import SwiftUI

struct EditorView: View {
    @ObservedObject var document: EditorDocument

    var body: some View {
        ZStack(alignment: .top) {
            HSplitView {
                VStack(spacing: 0) {
                    ImageCanvasView(document: document)
                    statusBar
                }
                .frame(minWidth: 580)

                InspectorView(document: document)
                    .frame(minWidth: 310, idealWidth: 348, maxWidth: 410)
            }

            if let errorMessage = document.errorMessage {
                ErrorBanner(message: errorMessage) {
                    document.dismissError()
                }
                .frame(maxWidth: 620)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand {
            if document.isAddingText {
                document.cancelAddingText()
            } else {
                document.select(nil)
            }
        }
        .onDeleteCommand {
            document.resetSelectedRegion()
        }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if document.isOCRRunning || document.isExporting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Text(document.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if document.hasImage {
                MetadataPill(
                    text: "\(document.regions.count) text regions",
                    systemImage: "character.textbox"
                )
                MetadataPill(
                    text: "\(Int(document.pixelSize.width)) × \(Int(document.pixelSize.height)) px",
                    systemImage: "photo"
                )
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
