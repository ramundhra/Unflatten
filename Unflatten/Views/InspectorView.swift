import AppKit
import SwiftUI

struct InspectorView: View {
    @ObservedObject var document: EditorDocument
    @FocusState private var replacementIsFocused: Bool
    @State private var confirmsResetAll = false

    private let maximumFontSize: CGFloat = 300
    private let fontFamilies = NSFontManager.shared.availableFontFamilies.sorted {
        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
    }

    var body: some View {
        Group {
            if let region = document.selectedRegion {
                inspector(for: region)
            } else {
                emptyInspector
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onChange(of: document.editingRequestToken) {
            if document.editingRegionID == document.selectedRegionID {
                replacementIsFocused = true
            }
        }
        .confirmationDialog(
            "Reset all text edits?",
            isPresented: $confirmsResetAll,
            titleVisibility: .visible
        ) {
            Button("Reset All Edits", role: .destructive) {
                document.resetAllEdits()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The imported image remains untouched. This action can be undone.")
        }
    }

    private var emptyInspector: some View {
        VStack(spacing: 12) {
            Image(systemName: "selection.pin.in.out")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("Select a text line")
                .font(.headline)
            Text("Click an outlined line in the image to edit all of its text and style.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func inspector(for region: TextRegion) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(region.source == .added ? "ADDED TEXT" : "TEXT LINE")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(
                        region.source == .added
                            ? "New text layer"
                            : region.originalText
                    )
                        .font(.body.weight(.medium))
                        .textSelection(.enabled)
                    if region.source == .ocr {
                        Text("OCR confidence \(Int((region.confidence * 100).rounded()))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(region.source == .added ? "Text" : "Line replacement")
                        .font(.headline)
                    TextField(
                            "Replacement line",
                        text: Binding(
                            get: { document.region(id: region.id)?.replacementText ?? "" },
                            set: { document.setReplacementText($0, for: region.id) }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(1...4)
                    .focused($replacementIsFocused)

                    Toggle(
                        "Math formatting",
                        isOn: Binding(
                            get: {
                                document.region(id: region.id)?
                                    .style.mathFormattingEnabled
                                    ?? region.style.mathFormattingEnabled
                            },
                            set: {
                                document.setMathFormattingEnabled(
                                    $0,
                                    for: region.id
                                )
                            }
                        )
                    )

                    if (document.region(id: region.id)?
                        .style.mathFormattingEnabled
                        ?? region.style.mathFormattingEnabled) {
                        HStack(spacing: 7) {
                            Button("x₂") {
                                document.insertMathMarkup(
                                    "_{2}",
                                    for: region.id
                                )
                            }
                            .help("Append a subscript template")

                            Button("x²") {
                                document.insertMathMarkup(
                                    "^{2}",
                                    for: region.id
                                )
                            }
                            .help("Append a superscript template")

                            Button("a⁄b") {
                                document.insertMathMarkup(
                                    "\\frac{a}{b}",
                                    for: region.id
                                )
                            }
                            .help("Append a fraction template")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Text(
                            "Use H_{2}O, x^{2}, \\frac{a}{b}, \\sqrt{x}, or symbols such as \\alpha and \\pi."
                        )
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("Typography")
                        .font(.headline)

                    FontFamilyPicker(
                        selection: Binding(
                            get: { document.region(id: region.id)?.style.fontFamily ?? region.style.fontFamily },
                            set: { document.setFontFamily($0, for: region.id) }
                        ),
                        families: fontFamilies
                    )
                    .frame(height: 25)

                    HStack {
                        Text("Size")
                        Slider(
                            value: Binding(
                                get: { Double(document.region(id: region.id)?.style.fontSize ?? region.style.fontSize) },
                                set: { document.setFontSize(CGFloat($0), for: region.id) }
                            ),
                            in: Double(TextRenderer.minimumFontSize)...Double(maximumFontSize)
                        )

                        Button {
                            adjustFontSize(by: -1, for: region)
                        } label: {
                            Image(systemName: "minus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Decrease font size")
                        .help("Decrease font size by 1 point")
                        .disabled(
                            currentFontSize(for: region)
                                <= TextRenderer.minimumFontSize
                        )

                        TextField(
                            "Size",
                            value: Binding(
                                get: { Double(document.region(id: region.id)?.style.fontSize ?? region.style.fontSize) },
                                set: { document.setFontSize(CGFloat($0), for: region.id) }
                            ),
                            format: .number.precision(.fractionLength(0...1))
                        )
                        .frame(width: 48)
                        .multilineTextAlignment(.trailing)

                        Button {
                            adjustFontSize(by: 1, for: region)
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Increase font size")
                        .help("Increase font size by 1 point")
                        .disabled(currentFontSize(for: region) >= maximumFontSize)
                    }

                    renderedSizeLabel(for: region)

                    Picker(
                        "Weight",
                        selection: Binding(
                            get: { document.region(id: region.id)?.style.weight ?? region.style.weight },
                            set: { document.setWeight($0, for: region.id) }
                        )
                    ) {
                        ForEach(TextWeight.allCases) { weight in
                            Text(weight.title).tag(weight)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker(
                        "Alignment",
                        selection: Binding(
                            get: { document.region(id: region.id)?.style.alignment ?? region.style.alignment },
                            set: { document.setAlignment($0, for: region.id) }
                        )
                    ) {
                        Image(systemName: "text.alignleft").tag(TextAlignmentOption.left)
                        Image(systemName: "text.aligncenter").tag(TextAlignmentOption.center)
                        Image(systemName: "text.alignright").tag(TextAlignmentOption.right)
                    }
                    .pickerStyle(.segmented)

                    ColorPicker(
                        "Text color",
                        selection: Binding(
                            get: {
                                (document.region(id: region.id)?.style.textColor ?? region.style.textColor)
                                    .swiftUIColor
                            },
                            set: { document.setTextColor(RGBAColor(nsColor: NSColor($0)), for: region.id) }
                        ),
                        supportsOpacity: true
                    )

                    Picker(
                        "Text area",
                        selection: Binding(
                            get: {
                                document.region(id: region.id)?.style.textAreaSizingMode
                                    ?? region.style.textAreaSizingMode
                            },
                            set: { document.setTextAreaSizingMode($0, for: region.id) }
                        )
                    ) {
                        ForEach(TextAreaSizingMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if (document.region(id: region.id)?.style.textAreaSizingMode
                        ?? region.style.textAreaSizingMode) == .custom {
                        HStack {
                            Text("Area width")
                            Slider(
                                value: Binding(
                                    get: {
                                        Double(
                                            document.region(id: region.id)?
                                                .style.customAreaWidthScale
                                                ?? region.style.customAreaWidthScale
                                        )
                                    },
                                    set: {
                                        document.setCustomAreaWidthScale(
                                            CGFloat($0),
                                            for: region.id
                                        )
                                    }
                                ),
                                in: Double(TextStyle.minimumCustomAreaScale)
                                    ... Double(TextStyle.maximumCustomAreaWidthScale)
                            )
                            Text(
                                Double(
                                    document.region(id: region.id)?
                                        .style.customAreaWidthScale
                                        ?? region.style.customAreaWidthScale
                                ),
                                format: .number.precision(.fractionLength(1))
                            )
                            .font(.caption.monospacedDigit())
                            .frame(width: 30, alignment: .trailing)
                        }

                        HStack {
                            Text("Area height")
                            Slider(
                                value: Binding(
                                    get: {
                                        Double(
                                            document.region(id: region.id)?
                                                .style.customAreaHeightScale
                                                ?? region.style.customAreaHeightScale
                                        )
                                    },
                                    set: {
                                        document.setCustomAreaHeightScale(
                                            CGFloat($0),
                                            for: region.id
                                        )
                                    }
                                ),
                                in: Double(TextStyle.minimumCustomAreaScale)
                                    ... Double(TextStyle.maximumCustomAreaHeightScale)
                            )
                            Text(
                                Double(
                                    document.region(id: region.id)?
                                        .style.customAreaHeightScale
                                        ?? region.style.customAreaHeightScale
                                ),
                                format: .number.precision(.fractionLength(1))
                            )
                            .font(.caption.monospacedDigit())
                            .frame(width: 30, alignment: .trailing)
                        }

                        Text(
                            "Shrink or enlarge the drawing area. Values below 1.0 make it smaller than the original."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Toggle(
                        "Shrink to Fit",
                        isOn: Binding(
                            get: { document.region(id: region.id)?.style.shrinkToFit ?? region.style.shrinkToFit },
                            set: { document.setShrinkToFit($0, for: region.id) }
                        )
                    )
                }

                Divider()

                if region.requiresBackgroundCleanup {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Background cleanup")
                            .font(.headline)

                        HStack {
                            Text(region.backgroundIsSimple ? "Simple background" : "Complex background")
                            Spacer()
                            Text("\(Int((region.backgroundUniformity * 100).rounded()))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Picker(
                            "Cleanup method",
                            selection: Binding(
                                get: {
                                    document.region(id: region.id)?.style.backgroundCleanupMode
                                        ?? region.style.backgroundCleanupMode
                                },
                                set: { document.setBackgroundCleanupMode($0, for: region.id) }
                            )
                        ) {
                            ForEach(BackgroundCleanupMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        if (document.region(id: region.id)?.style.backgroundCleanupMode
                            ?? region.style.backgroundCleanupMode) == .photoAware {
                            Text(
                                "Reconstructs the old text area from nearby pixels. This runs locally and works best on paper, gradients, and light textures."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ColorPicker(
                                "Background color",
                                selection: Binding(
                                    get: {
                                        (document.region(id: region.id)?.style.backgroundColor
                                            ?? region.style.backgroundColor)
                                            .swiftUIColor
                                    },
                                    set: {
                                        document.setBackgroundColor(
                                            RGBAColor(nsColor: NSColor($0)),
                                            for: region.id
                                        )
                                    }
                                ),
                                supportsOpacity: true
                            )

                            Toggle(
                                "Use custom background",
                                isOn: Binding(
                                    get: {
                                        document.region(id: region.id)?.style.usesManualBackground
                                            ?? region.style.usesManualBackground
                                    },
                                    set: { document.setUsesManualBackground($0, for: region.id) }
                                )
                            )

                            if !region.backgroundIsSimple && !region.style.usesManualBackground {
                                warningLabel(
                                    "The surrounding pixels are not uniform. Use Photo-aware cleanup, or choose a background color and enable the custom background."
                                )
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Background")
                            .font(.headline)
                        Text(
                            "Added text is composited over the existing image, so no background pixels are erased. Drag its outline on the canvas to move it."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let warning = document.warning(for: region.id) {
                    warningLabel(warning.message)
                } else if !fitResult(for: region).fits {
                    warningLabel("The replacement cannot fit inside the image at the selected font size.")
                } else if region.imageBoundingBox.height < 7 {
                    warningLabel("This text line is extremely small.")
                }

                Divider()

                VStack(spacing: 8) {
                    if region.source == .added {
                        Button("Delete Text", role: .destructive) {
                            document.deleteRegion(region.id)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Button("Reset Line") {
                            document.resetRegion(region.id)
                        }
                        .frame(maxWidth: .infinity)
                        .disabled(!region.isEdited)
                    }

                    Button("Reset All Edits") {
                        confirmsResetAll = true
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(!document.regions.contains(where: \.isEdited))
                }
            }
            .padding(16)
        }
    }

    private func fitResult(for region: TextRegion) -> TextFitResult {
        let rect = TextRenderer
            .drawingRect(for: region, imageSize: document.pixelSize)
            .insetBy(dx: 1, dy: 1)
        return TextRenderer.fit(text: region.replacementText, style: region.style, in: rect.size)
    }

    private func currentFontSize(for region: TextRegion) -> CGFloat {
        document.region(id: region.id)?.style.fontSize ?? region.style.fontSize
    }

    private func adjustFontSize(by amount: CGFloat, for region: TextRegion) {
        document.setFontSize(
            currentFontSize(for: region) + amount,
            for: region.id
        )
    }

    private func renderedSizeLabel(for region: TextRegion) -> some View {
        let currentRegion = document.region(id: region.id) ?? region
        let result = fitResult(for: currentRegion)

        return HStack {
            Text("Rendered size")
            Spacer()
            Text(
                Double(result.fontSize),
                format: .number.precision(.fractionLength(1))
            )
            .monospacedDigit()
            Text("pt")
        }
        .font(.caption)
        .foregroundStyle(
            result.fontSize + 0.05 < currentRegion.style.fontSize
                ? Color.orange
                : Color.secondary
        )
    }

    private func warningLabel(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
    }
}
