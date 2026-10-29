import SwiftUI

extension View {
    /// Full-width padding and hover highlight shared by list rows.
    func rowStyle(isHovered: Bool) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isHovered ? Color.primary.opacity(0.08) : .clear, in: .rect(cornerRadius: 6))
            .contentShape(.rect)
    }
}
