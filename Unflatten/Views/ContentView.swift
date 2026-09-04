import SwiftUI

struct ContentView: View {
    @ObservedObject var document: EditorDocument

    var body: some View {
        Group {
            if document.hasImage {
                EditorView(document: document)
            } else {
                WelcomeView(document: document)
            }
        }
        .frame(minWidth: 940, minHeight: 640)
        .tint(.accentColor)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    document.openImage()
                } label: {
                    Label("Open", systemImage: "folder")
                }
                .help("Open Image (⌘O)")

                Button {
                    document.pasteImage()
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .help("Paste an image")
            }

            if document.hasImage {
                ToolbarItemGroup {
                    Button {
                        document.runOCR()
                    } label: {
                        Label("Scan Text", systemImage: "viewfinder")
                    }
                    .disabled(document.isOCRRunning)

                    Button {
                        document.toggleAddingText()
                    } label: {
                        Label(
                            document.isAddingText ? "Cancel Add Text" : "Add Text",
                            systemImage: document.isAddingText ? "xmark" : "text.badge.plus"
                        )
                    }
                    .help(
                        document.isAddingText
                            ? "Cancel placing new text"
                            : "Add text at a point in the image"
                    )
                    .disabled(document.isOCRRunning)

                    Divider()

                    Button {
                        document.undo()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!document.canUndo)

                    Button {
                        document.redo()
                    } label: {
                        Label("Redo", systemImage: "arrow.uturn.forward")
                    }
                    .disabled(!document.canRedo)
                }

                ToolbarItem(placement: .principal) {
                    Picker("Preview", selection: $document.isShowingBefore) {
                        Text("Edited").tag(false)
                        Text("Original").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 172)
                    .help("Switch between the original and edited image")
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        document.copyResult()
                    } label: {
                        Label("Copy Result", systemImage: "doc.on.doc")
                    }
                    .disabled(document.isExporting)

                    Button {
                        document.exportPNG()
                    } label: {
                        Label("Export PNG", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(document.isExporting)
                }
            }
        }
    }
}
