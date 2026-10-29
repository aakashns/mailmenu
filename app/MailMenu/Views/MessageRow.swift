import SwiftUI

/// One unread message: sender name and email on the first line, subject on the second,
/// and buttons to archive (or delete, while Shift is held) and unsubscribe (or block) when hovered.
/// Clicking anywhere else opens it in the browser. Blocking asks for confirmation inside the row first,
/// and once an action is done the row shows `acknowledgement` until it's removed.
struct MessageRow: View {
    let message: UnreadMessage
    let acknowledgement: String?
    let archive: () -> Void
    let delete: () -> Void
    let unsubscribe: () -> Void
    let blockAndReportSpam: () -> Void
    let open: () -> Void
    @State private var isHovered = false
    @State private var isShiftHeld = false
    @State private var modifierMonitor: Any?
    @State private var isConfirmingBlock = false

    private var isCovered: Bool { isConfirmingBlock || acknowledgement != nil }

    var body: some View {
        // The message stays in the layout (invisible) under the overlay, so the row keeps its height.
        messageContent
            .opacity(isCovered ? 0 : 1)
            .allowsHitTesting(!isCovered)
            .accessibilityHidden(isCovered)
            .overlay {
                if let acknowledgement {
                    acknowledgementView(acknowledgement)
                } else if isConfirmingBlock {
                    blockConfirmation
                }
            }
            .rowStyle(isHovered: (isHovered && acknowledgement == nil) || isConfirmingBlock)
            .onHover { isHovered = $0 }
            .onChange(of: isHovered) { _, hovered in
                hovered ? startTrackingShift() : stopTrackingShift()
            }
            .onDisappear(perform: stopTrackingShift)
    }

    /// Shift is only checked while hovered, so only the hovered row listens for modifier key changes.
    private func startTrackingShift() {
        isShiftHeld = NSEvent.modifierFlags.contains(.shift)
        modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            isShiftHeld = event.modifierFlags.contains(.shift)
            return event
        }
    }

    private func stopTrackingShift() {
        if let modifierMonitor {
            NSEvent.removeMonitor(modifierMonitor)
        }
        modifierMonitor = nil
        isShiftHeld = false
    }

    private func acknowledgementView(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .fontWeight(.semibold)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
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
                    Button(action: isShiftHeld ? delete : archive) {
                        Image(systemName: isShiftHeld ? "trash" : "archivebox")
                    }
                    .help(isShiftHeld ? "Delete" : "Archive (hold Shift to delete)")
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
