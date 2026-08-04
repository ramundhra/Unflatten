import AppKit
import SwiftUI

struct FontFamilyPicker: NSViewRepresentable {
    @Binding var selection: String
    let families: [String]

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.delegate = context.coordinator
        comboBox.isEditable = true
        comboBox.completes = true
        comboBox.numberOfVisibleItems = 12
        comboBox.addItems(withObjectValues: families)
        comboBox.stringValue = selection
        comboBox.placeholderString = "Font family"
        return comboBox
    }

    func updateNSView(_ comboBox: NSComboBox, context: Context) {
        if comboBox.numberOfItems != families.count {
            comboBox.removeAllItems()
            comboBox.addItems(withObjectValues: families)
        }
        if comboBox.stringValue != selection {
            comboBox.stringValue = selection
        }
    }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        private var selection: Binding<String>

        init(selection: Binding<String>) {
            self.selection = selection
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            selection.wrappedValue = comboBox.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            selection.wrappedValue = comboBox.stringValue
        }
    }
}

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.orange.opacity(0.35))
        }
        .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
    }
}
