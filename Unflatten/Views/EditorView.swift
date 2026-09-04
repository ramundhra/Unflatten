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
                .frame(minWidth: 520)

                InspectorView(document: document)
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
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
        HStack(spacing: 9) {
            if document.isOCRRunning || document.isExporting {
                ProgressView()
                    .controlSize(.small)
            }

            Text(document.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if document.hasImage {
                Text("\(Int(document.pixelSize.width)) × \(Int(document.pixelSize.height)) px")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
