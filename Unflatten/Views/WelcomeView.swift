import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @ObservedObject var document: EditorDocument
    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            UnflattenTheme.welcomeBackground
                .ignoresSafeArea()

            Circle()
                .fill(Color.accentColor.opacity(0.10))
                .frame(width: 360, height: 360)
                .blur(radius: 50)
                .offset(x: -330, y: -230)

            Circle()
                .fill(Color.purple.opacity(0.08))
                .frame(width: 300, height: 300)
                .blur(radius: 55)
                .offset(x: 360, y: 250)

            VStack(spacing: 26) {
                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.accentColor,
                                        Color.accentColor.opacity(0.72)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 70, height: 70)
                            .shadow(color: Color.accentColor.opacity(0.25), radius: 16, y: 8)

                        Image(systemName: "character.textbox")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityHidden(true)

                    VStack(spacing: 8) {
                        Text("Unflatten")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                        Text("Make text in any image editable again.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        document.openImage()
                    } label: {
                        Label("Open Image", systemImage: "folder")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut("o", modifiers: .command)

                    Button {
                        document.pasteImage()
                    } label: {
                        Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                VStack(spacing: 11) {
                    Image(
                        systemName: isDropTargeted
                            ? "arrow.down.doc.fill"
                            : "photo.on.rectangle.angled"
                    )
                        .font(.system(size: 27, weight: .medium))
                        .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary)
                    Text(isDropTargeted ? "Drop to open" : "Drop a PNG, JPEG, or HEIC image here")
                        .font(.callout.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 112)
                .background(Color.accentColor.opacity(isDropTargeted ? 0.10 : 0.035))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            isDropTargeted ? Color.accentColor : UnflattenTheme.border,
                            style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [6, 5])
                        )
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .scaleEffect(isDropTargeted ? 1.012 : 1)
                .animation(.easeOut(duration: 0.15), value: isDropTargeted)

                HStack(spacing: 18) {
                    Label("On-device OCR", systemImage: "text.viewfinder")
                    Label("Private by design", systemImage: "lock.shield")
                    Label("Pixel-perfect export", systemImage: "sparkles")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

                if let errorMessage = document.errorMessage {
                    ErrorBanner(message: errorMessage) {
                        document.dismissError()
                    }
                    .frame(maxWidth: 500)
                }
            }
            .padding(38)
            .frame(maxWidth: 590)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.10), radius: 28, y: 14)
            .padding(42)
        }
        .onDrop(
            of: [UTType.fileURL.identifier, UTType.image.identifier],
            isTargeted: $isDropTargeted
        ) { providers in
            document.handleDrop(providers: providers)
        }
    }
}
