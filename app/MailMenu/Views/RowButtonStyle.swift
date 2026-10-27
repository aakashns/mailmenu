import SwiftUI

/// A full-width list row that highlights on hover, used for messages and events.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(label: configuration.label)
    }

    private struct Row: View {
        let label: Configuration.Label
        @State private var isHovered = false

        var body: some View {
            label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(isHovered ? Color.primary.opacity(0.08) : .clear, in: .rect(cornerRadius: 6))
                .contentShape(.rect)
                .onHover { isHovered = $0 }
        }
    }
}

extension ButtonStyle where Self == RowButtonStyle {
    static var row: RowButtonStyle { RowButtonStyle() }
}
