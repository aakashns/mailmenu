import SwiftUI

/// One unread message: sender name and email on the first line, subject on the second,
/// and buttons to archive and unsubscribe when hovered. Holding Shift turns them into delete and block
/// (block is also the button for messages that can't be unsubscribed from).
/// Clicking anywhere else opens it in the browser. Blocking asks for confirmation inside the row first,
/// and once an action is done the row shows `acknowledgement` until it's removed.
struct MessageRow: View {
    let message: UnreadMessage
    let acknowledgement: String?
    /// Whether an action on the message is in progress (waiting for Gmail).
    let isPending: Bool
    let archive: () -> Void
    let delete: () -> Void
    let unsubscribe: () -> Void
    let blockAndReportSpam: () -> Void
    /// Fetches the start of the message's text; nil if it couldn't be loaded.
    let loadPreview: () async -> String?
    let open: () -> Void
    @State private var preview: String?
    @State private var isShowingPreview = false
    @State private var isHovered = false
    @State private var isShiftHeld = false
    @State private var modifierMonitor: Any?
    @State private var isConfirmingBlock = false

    private var isCovered: Bool { isConfirmingBlock || isPending || acknowledgement != nil }

    var body: some View {
        // The message stays in the layout (invisible) under the overlay, so the row keeps its height.
        messageContent
            .opacity(isCovered ? 0 : 1)
            .allowsHitTesting(!isCovered)
            .accessibilityHidden(isCovered)
            .overlay {
                if let acknowledgement {
                    acknowledgementView(acknowledgement)
                } else if isPending {
                    pendingView
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
            .task(id: isHovered && !isCovered) { await showPreviewAfterDelay() }
            .popover(isPresented: $isShowingPreview, arrowEdge: .leading) {
                Group {
                    if let preview {
                        Text(preview)
                            .lineLimit(20)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(width: 320, alignment: .leading)
                .padding(12)
            }
    }

    /// Hovering briefly (not just passing over the row) loads the message text and shows it beside the menu.
    /// The task is cancelled, and the popover hidden, as soon as the pointer leaves.
    private func showPreviewAfterDelay() async {
        guard isHovered && !isCovered else {
            isShowingPreview = false
            return
        }
        // Start loading right away so the text is usually ready by the time the delay ends.
        let loading = Task { @MainActor in await loadPreview() }
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        if preview == nil {
            isShowingPreview = true // shows a spinner until the text arrives
            preview = await loading.value
        }
        guard !Task.isCancelled else { return }
        isShowingPreview = !(preview ?? "").isEmpty
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

    private var pendingView: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Working…")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
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
                    if message.unsubscribe != nil && !isShiftHeld {
                        Button(action: unsubscribe) {
                            Image(systemName: "bell.slash")
                        }
                        .help("Unsubscribe (hold Shift to block)")
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
