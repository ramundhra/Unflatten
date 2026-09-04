import SwiftUI

enum UnflattenTheme {
    static let cornerRadius: CGFloat = 12
    static let panelBackground = Color(nsColor: .windowBackgroundColor)
    static let cardBackground = Color(nsColor: .textBackgroundColor).opacity(0.72)
    static let border = Color(nsColor: .separatorColor).opacity(0.65)

    static let workspaceBackground = LinearGradient(
        colors: [
            Color(nsColor: .controlBackgroundColor).opacity(0.78),
            Color(nsColor: .windowBackgroundColor)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let welcomeBackground = LinearGradient(
        colors: [
            Color.accentColor.opacity(0.16),
            Color(nsColor: .windowBackgroundColor),
            Color.accentColor.opacity(0.06)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct InspectorSectionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .symbolRenderingMode(.hierarchical)
    }
}

struct MetadataPill: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(.caption2.weight(.medium))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.10), in: Capsule())
        .overlay {
            Capsule()
                .stroke(tint.opacity(0.18), lineWidth: 0.5)
        }
    }
}

extension View {
    func inspectorCard() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                UnflattenTheme.cardBackground,
                in: RoundedRectangle(
                    cornerRadius: UnflattenTheme.cornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: UnflattenTheme.cornerRadius,
                    style: .continuous
                )
                .stroke(UnflattenTheme.border, lineWidth: 0.5)
            }
    }
}
