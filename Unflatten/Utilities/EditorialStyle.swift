import AppKit
import SwiftUI

enum EditorialTheme {
    static let panel = Color(nsColor: .windowBackgroundColor)
    static let raised = Color(nsColor: .controlBackgroundColor)
    static let rule = Color(nsColor: .separatorColor).opacity(0.72)
    static let quietRule = Color(nsColor: .separatorColor).opacity(0.34)
}

private struct SubtleButtonHoverModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered && !reduceMotion ? 1.01 : 1)
            .offset(y: isHovered && !reduceMotion ? -1 : 0)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: isHovered
            )
            .onHover { hovering in
                guard hovering != isHovered else { return }
                isHovered = hovering

                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                guard isHovered else { return }
                NSCursor.pop()
                isHovered = false
            }
    }
}

extension View {
    func subtleButtonHover() -> some View {
        modifier(SubtleButtonHoverModifier())
    }
}

struct EditorialSectionHeader: View {
    let number: String
    let title: String

    var body: some View {
        HStack(spacing: 9) {
            Text(number)
                .font(.caption2.monospaced().weight(.bold))
                .foregroundStyle(.tint)

            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.secondary)

            Rectangle()
                .fill(EditorialTheme.quietRule)
                .frame(height: 1)
        }
    }
}

struct EditorMetadata: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(EditorialTheme.rule, lineWidth: 0.5)
            }
    }
}

struct WorkspaceGrid: View {
    private let spacing: CGFloat = 24

    var body: some View {
        Canvas { context, size in
            var path = Path()

            for x in stride(from: CGFloat.zero, through: size.width, by: spacing) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }

            for y in stride(from: CGFloat.zero, through: size.height, by: spacing) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }

            context.stroke(
                path,
                with: .color(Color.secondary.opacity(0.055)),
                lineWidth: 0.5
            )
        }
        .allowsHitTesting(false)
    }
}
