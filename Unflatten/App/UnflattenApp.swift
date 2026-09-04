import SwiftUI

@main
struct UnflattenApp: App {
    @StateObject private var document = EditorDocument()

    var body: some Scene {
        WindowGroup {
            ContentView(document: document)
        }
        .defaultSize(width: 1_100, height: 750)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Image…") {
                    document.openImage()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    document.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!document.canUndo)

                Button("Redo") {
                    document.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!document.canRedo)
            }

            CommandMenu("Image") {
                Button("Paste Image") {
                    document.pasteImage()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])

                Button("Run OCR Again") {
                    document.runOCR()
                }
                .disabled(!document.hasImage || document.isOCRRunning)

                Button(document.isAddingText ? "Cancel Add Text" : "Add Text") {
                    document.toggleAddingText()
                }
                .disabled(!document.hasImage || document.isOCRRunning)

                Divider()

                Button(document.isShowingBefore ? "Show After" : "Show Before") {
                    document.isShowingBefore.toggle()
                }
                .keyboardShortcut("\\", modifiers: .command)

                Divider()

                Button("Copy Result") {
                    document.copyResult()
                }
                .disabled(!document.hasImage || document.isExporting)

                Button("Export PNG…") {
                    document.exportPNG()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!document.hasImage || document.isExporting)
            }
        }
    }
}
