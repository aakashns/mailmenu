import SwiftUI

/// One unread message: sender name and email on the first line, subject on the second,
/// and buttons to archive, delete, unsubscribe (if the sender supports it) and block when hovered.
/// Clicking anywhere else opens it in the browser. Blocking asks for confirmation inside the row first.
struct MessageRow: View {
    let message: UnreadMessage
    let archive: () -> Void
    let snooze: (Date) -> Void
    let delete: () -> Void
    let unsubscribe: () -> Void
    let blockAndReportSpam: () -> Void
    /// Fetches the start of the message's text; nil if it couldn't be loaded.
    let loadPreview: () async -> String?
    let open: () -> Void
    @State private var preview: String?
    @State private var anchor = ScreenFrameAnchor()
    @State private var isHovered = false
    @State private var isConfirmingBlock = false
    @State private var isChoosingSnooze = false

    private var isCovered: Bool { isConfirmingBlock || isChoosingSnooze }

    var body: some View {
        // The message stays in the layout (invisible) under the overlay, so the row keeps its height.
        messageContent
            .opacity(isCovered ? 0 : 1)
            .allowsHitTesting(!isCovered)
            .accessibilityHidden(isCovered)
            .overlay {
                if isConfirmingBlock {
                    blockConfirmation
                } else if isChoosingSnooze {
                    snoozeOptions
                }
            }
            .rowStyle(isHovered: isHovered || isCovered)
            .onHover { isHovered = $0 }
            .onDisappear {
                PreviewPanel.shared.hide()
            }
            .task(id: isHovered && !isCovered) { await showPreviewAfterDelay() }
            .background(ScreenFrameReader(anchor: anchor))
    }

    /// Hovering briefly (not just passing over the row) loads the message text and shows it beside the menu.
    /// The task is cancelled, and the preview hidden, as soon as the pointer leaves.
    /// The preview is a separate non-activating panel rather than a popover, because a popover takes focus
    /// and the first click on a menu button would then only dismiss it instead of pressing the button.
    private func showPreviewAfterDelay() async {
        guard isHovered && !isCovered else {
            PreviewPanel.shared.hide()
            return
        }
        // Start loading right away so the text is usually ready by the time the delay ends.
        let loading = Task { @MainActor in await loadPreview() }
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled, let frame = anchor.screenFrame, let window = anchor.window else { return }
        if preview == nil {
            PreviewPanel.shared.show(nil, besideRow: frame, in: window) // shows a spinner until the text arrives
            preview = await loading.value
        }
        guard !Task.isCancelled, let text = preview, !text.isEmpty,
              let frame = anchor.screenFrame else {
            PreviewPanel.shared.hide()
            return
        }
        PreviewPanel.shared.show(text, besideRow: frame, in: window)
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
                    Button {
                        isChoosingSnooze = true
                    } label: {
                        Image(systemName: "clock")
                    }
                    .help("Snooze")
                    Button(action: delete) {
                        Image(systemName: "trash")
                    }
                    .help("Delete")
                    if message.unsubscribe != nil {
                        Button(action: unsubscribe) {
                            Image(systemName: "bell.slash")
                        }
                        .help("Unsubscribe")
                    }
                    Button {
                        isConfirmingBlock = true
                    } label: {
                        Image(systemName: "xmark.octagon")
                    }
                    .help("Block & report spam")
                }
                .buttonStyle(.borderless)
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: open)
    }

    /// Covers the message until the user picks a time or cancels.
    private var snoozeOptions: some View {
        HStack(spacing: 8) {
            Text("Snooze")
                .fontWeight(.semibold)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 0)
            ForEach(SnoozeOption.allCases, id: \.self) { option in
                Button(option.title) {
                    isChoosingSnooze = false
                    snooze(option.date())
                }
                .lineLimit(1)
                .fixedSize()
                .help(option.date().formatted(date: .complete, time: .shortened))
            }
            Button {
                isChoosingSnooze = false
            } label: {
                Image(systemName: "xmark")
            }
            .help("Cancel")
        }
        .controlSize(.small)
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

/// Lets a row find where it is on screen.
@MainActor
final class ScreenFrameAnchor {
    fileprivate weak var view: NSView?

    var window: NSWindow? { view?.window }

    var screenFrame: NSRect? {
        guard let view, let window = view.window else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
}

private struct ScreenFrameReader: NSViewRepresentable {
    let anchor: ScreenFrameAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.view = view
    }
}

/// A floating text preview shown to the left of the menu (or to the right if there's no room).
/// It never becomes the key window and ignores the mouse, so the menu keeps focus and clicks go through.
@MainActor
final class PreviewPanel {
    static let shared = PreviewPanel()

    private var panel: NSPanel?
    private var observers: [NSObjectProtocol] = []
    private static let width: CGFloat = 344

    /// Shows `text`, or a spinner if it's nil, aligned with the top of the row.
    func show(_ text: String?, besideRow row: NSRect, in menuWindow: NSWindow) {
        let panel = panel ?? makePanel()
        self.panel = panel

        let hosting = NSHostingView(rootView: PreviewContent(text: text).frame(width: Self.width))
        let size = hosting.fittingSize
        panel.contentView = hosting

        let screen = menuWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let gap: CGFloat = 6
        var x = menuWindow.frame.minX - size.width - gap
        if x < screen.minX { x = menuWindow.frame.maxX + gap }
        let y = min(max(row.maxY - size.height, screen.minY), screen.maxY - size.height)
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
        panel.orderFrontRegardless()

        if observers.isEmpty {
            observers = [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification].map {
                NotificationCenter.default.addObserver(forName: $0, object: menuWindow, queue: .main) { _ in
                    MainActor.assumeIsolated { PreviewPanel.shared.hide() }
                }
            }
        }
    }

    func hide() {
        panel?.orderOut(nil)
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        return panel
    }
}

private struct PreviewContent: View {
    let text: String?

    var body: some View {
        Group {
            if let text {
                Text(text)
                    .lineLimit(20)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
    }
}

/// When a snoozed message comes back, always at 8:00 in the morning.
private enum SnoozeOption: CaseIterable {
    case tomorrow, weekend, nextWeek

    var title: String {
        switch self {
        case .tomorrow: "Tomorrow"
        case .weekend: "Weekend"
        case .nextWeek: "Next week"
        }
    }

    func date(from now: Date = .now) -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let weekday: Int
        switch self {
        case .tomorrow: return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow)!
        case .weekend: weekday = 7 // Saturday
        case .nextWeek: weekday = 2 // Monday
        }
        return calendar.nextDate(after: now, matching: DateComponents(hour: 8, minute: 0, weekday: weekday),
                                 matchingPolicy: .nextTime) ?? tomorrow
    }
}
