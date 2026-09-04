import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @ObservedObject var document: EditorDocument
    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 54, weight: .medium))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(spacing: 7) {
                    Text("Unflatten")
                        .font(.system(size: 32, weight: .semibold))
                    Text("Edit text inside flattened screenshots.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button("Open Image") {
                        document.openImage()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut("o", modifiers: .command)

                    Button("Paste Image") {
                        document.pasteImage()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                VStack(spacing: 9) {
                    Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "photo.on.rectangle.angled")
                        .font(.title2)
                        .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary)
                    Text(isDropTargeted ? "Drop to open" : "Drop a PNG, JPEG, or HEIC image here")
                        .font(.callout.weight(.medium))
                    Text("Images, OCR, and edits stay on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 390, height: 116)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                            style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [6, 5])
                        )
                }
                .animation(.easeOut(duration: 0.12), value: isDropTargeted)

                if let errorMessage = document.errorMessage {
                    ErrorBanner(message: errorMessage) {
                        document.dismissError()
                    }
                    .frame(maxWidth: 500)
                }
            }
            .padding(40)
        }
        .onDrop(
            of: [UTType.fileURL.identifier, UTType.image.identifier],
            isTargeted: $isDropTargeted
        ) { providers in
            document.handleDrop(providers: providers)
        }
    }
}
