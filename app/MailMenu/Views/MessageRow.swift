import SwiftUI

/// One unread message: sender name and email on the first line, subject on the second,
/// and buttons to archive and unsubscribe (or block) when hovered. Clicking anywhere else opens it in
/// the browser. Blocking asks for confirmation inside the row first.
struct MessageRow: View {
    let message: UnreadMessage
    let archive: () -> Void
    let unsubscribe: () -> Void
    let blockAndReportSpam: () -> Void
    let open: () -> Void
    @State private var isHovered = false
    @State private var isConfirmingBlock = false

    var body: some View {
        // The message stays in the layout (invisible) under the confirmation, so the row keeps its height.
        messageContent
            .opacity(isConfirmingBlock ? 0 : 1)
            .allowsHitTesting(!isConfirmingBlock)
            .accessibilityHidden(isConfirmingBlock)
            .overlay {
                if isConfirmingBlock {
                    blockConfirmation
                }
            }
            .rowStyle(isHovered: isHovered || isConfirmingBlock)
            .onHover { isHovered = $0 }
    }

    private var messageContent: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if let name = message.senderName {
                        Text(name).fontWeight(.semibold)
                        Text(message.senderEmail).foregroundStyle(.secondary)
                    } else {
                        Text(message.senderEmail).fontWeight(.semibold)
                    }
                }
                .lineLimit(1)

                Text(message.subject.isEmpty ? "(no subject)" : message.subject)
                    .lineLimit(1)
            }
            // Fill the row up to the action buttons, so clicks and the tooltip cover the empty space too.
            // The tooltip goes here rather than on the whole row so it doesn't override the buttons' tooltips.
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .help(isConfirmingBlock ? "" : "Open in browser")
            if isHovered {
                HStack(spacing: 10) {
                    Button(action: archive) {
                        Image(systemName: "archivebox")
                    }
                    .help("Archive")
                    if message.unsubscribe != nil {
                        Button(action: unsubscribe) {
                            Image(systemName: "bell.slash")
                        }
                        .help("Unsubscribe")
                    } else {
                        Button {
                            isConfirmingBlock = true
                        } label: {
                            Image(systemName: "xmark.octagon")
                        }
                        .help("Block & report spam")
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: open)
    }

    /// Covers the message until the user confirms or cancels.
    private var blockConfirmation: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Block \(message.senderEmail)?")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Reports spam and trashes their future mail.")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button("Cancel") {
                isConfirmingBlock = false
            }
            Button("Block", role: .destructive) {
                isConfirmingBlock = false
                blockAndReportSpam()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .controlSize(.small)
    }
}
