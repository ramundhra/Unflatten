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
                .frame(minWidth: 560)

                InspectorView(document: document)
                    .frame(minWidth: 300, idealWidth: 336, maxWidth: 390)
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
                EditorMetadata(
                    text: "\(document.regions.count) regions",
                    systemImage: "character.textbox"
                )
                EditorMetadata(
                    text: "\(Int(document.pixelSize.width)) × \(Int(document.pixelSize.height)) px",
                    systemImage: "photo"
                )
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
