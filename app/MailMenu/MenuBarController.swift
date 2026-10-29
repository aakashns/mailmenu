import AppKit
import SwiftUI

/// The menu bar icon and the panel it opens.
///
/// This replaces SwiftUI's `MenuBarExtra`, which resizes its window a few frames after the content changes:
/// whenever the content got shorter (deleting a message, collapsing an account) it was drawn off-center and then
/// shifted back. Owning the window lets the panel resize in the same pass as its content.
final class MenuBarController: NSObject {
    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel = MenuPanel()
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    /// Changed every time the panel opens, so it starts fresh (no leftover hover or confirmation state).
    private var session = 0
    private var staysOpen = false

    init(model: AppModel) {
        self.model = model
        super.init()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        panel.onClose = { [weak self] in self?.close(returningFocus: true) }
        updateIcon()
    }

    /// Opens the panel and runs `DemoScript` in it. The panel stays open even when clicking elsewhere, so using
    /// the Mac meanwhile doesn't interfere.
    func runDemoScript() {
        staysOpen = true
        open()
        Task { await DemoScript(model: model, panel: panel).run() }
    }

    /// Redraws the menu bar icon now and whenever the unread count changes.
    private func updateIcon() {
        let count = withObservationTracking {
            model.totalUnreadCount
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateIcon() }
        }
        guard let button = statusItem.button else { return }
        button.image = MenuBarIcon.image(unreadCount: count) ?? NSImage(systemSymbolName: "envelope", accessibilityDescription: nil)
        button.setAccessibilityLabel(count > 0 ? "Mail Menu, \(count) unread" : "Mail Menu")
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            close(returningFocus: true)
        } else {
            open()
        }
    }

    func open() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        session += 1
        panel.setContent(MenuContentView().environment(model).id(session))
        panel.show(below: buttonWindow.convertToScreen(button.convert(button.bounds, to: nil)),
                   on: buttonWindow.screen ?? NSScreen.main)
        button.highlight(true)
        Task { await model.refreshAll() }
        guard !staysOpen else { return }

        // Close on any click outside the panel (including other apps' menu bar items), like a menu.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close(returningFocus: false) }
        }) {
            monitors.append(monitor)
        }
        // Also close when something else takes focus, e.g. the sign-in window or a link opening in the browser.
        // Clicking the menu bar icon is left to `togglePanel`, or the panel would close and immediately reopen.
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isPressingStatusItem else { return }
                self.close(returningFocus: false)
            }
        })
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close(returningFocus: false) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close(returningFocus: false) }
        })
    }

    /// Hides the panel. When it's closed from the keyboard or the menu bar icon, focus goes back to the app the user was in,
    /// unless another Mail Menu window (the sign-in window) is open.
    private func close(returningFocus: Bool) {
        guard panel.isVisible else { return }
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        observers.forEach(NotificationCenter.default.removeObserver)
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
        workspaceObservers = []
        PreviewPanel.shared.hide()
        panel.orderOut(nil)
        statusItem.button?.highlight(false)

        let hasOtherWindows = NSApp.windows.contains { $0 !== panel && $0.isVisible && $0.canBecomeKey }
        if returningFocus, NSApp.isActive, !hasOtherWindows {
            NSApp.hide(nil)
        }
    }

    private var isPressingStatusItem: Bool {
        guard NSEvent.pressedMouseButtons != 0, let button = statusItem.button, let window = button.window else { return false }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(NSEvent.mouseLocation)
    }
}

/// The window below the menu bar icon. It always fits its content, growing and shrinking from the bottom edge.
final class MenuPanel: NSPanel {
    /// Called when the user presses Escape or ⌘W.
    var onClose: (() -> Void)?
    private let hostingView = FittingHostingView(rootView: AnyView(EmptyView()))

    private static let cornerRadius: CGFloat = 10
    /// Space between the menu bar and the panel.
    private static let gap: CGFloat = 2

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        hostingView.sizingOptions = [.intrinsicContentSize]
        contentView = hostingView
    }

    override var canBecomeKey: Bool { true }

    func setContent(_ content: some View) {
        hostingView.rootView = AnyView(content
            // SwiftUI can update the content without AppKit laying out the hosting view, so this resizes the window too.
            .onGeometryChange(for: CGSize.self, of: \.size) { [weak self] size in
                self?.laidOutContentSize = size
                if self?.isVisible == true { self?.fit(size) }
            }
            // Pinned to the top, so if the window is ever taller than the content for a moment, the bottom edge is what moves.
            .frame(maxHeight: .infinity, alignment: .top)
            .background(.thinMaterial)
            .clipShape(.rect(cornerRadius: Self.cornerRadius)))
    }

    /// Opens the panel with its top-left corner under the menu bar icon, or its right edge aligned with the icon's
    /// if it would otherwise run off the screen.
    func show(below item: NSRect, on screen: NSScreen?) {
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.intrinsicContentSize
        let visible = screen?.visibleFrame ?? .infinite
        var x = item.minX
        if x + size.width > visible.maxX { x = item.maxX - size.width }
        x = max(x, visible.minX)
        setFrame(NSRect(x: x, y: item.minY - Self.gap - size.height, width: size.width, height: size.height), display: true)
        // Closing from the keyboard hides the app to hand focus back, and a hidden app's windows stay hidden.
        NSApp.unhideWithoutActivation()
        NSApp.activate()
        makeKeyAndOrderFront(nil)
        // In case the content changed while the panel was being shown.
        fit(hostingView.intrinsicContentSize)
    }

    /// Keeps the top edge in place when the content's size changes.
    fileprivate func fit(_ size: NSSize) {
        guard size != frame.size, size.width > 0, size.height > 0 else { return }
        setFrame(NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height), display: false)
        invalidateShadow()
    }

    /// The size of the content as last laid out.
    private(set) var laidOutContentSize: CGSize = .zero

    /// The panel as a PNG, drawn by the app itself so it needs no screen recording permission. The translucent
    /// background is replaced with a plain one, since only the window server can draw it.
    func snapshot() -> Data? {
        guard let layer = hostingView.layer else { return nil }
        let scale = backingScaleFactor
        let size = hostingView.bounds.size
        guard let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            context.addPath(CGPath(roundedRect: hostingView.bounds, cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius, transform: nil))
            context.setFillColor(NSColor.windowBackgroundColor.cgColor)
            context.fillPath()
        }
        // Layers draw top-down.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        layer.render(in: context)
        return context.makeImage().flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
    }

    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onClose?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func performClose(_ sender: Any?) {
        onClose?()
    }
}

/// Resizes its window to fit the SwiftUI content during layout, before anything is drawn, so the window and
/// the content always change size in the same frame.
private final class FittingHostingView: NSHostingView<AnyView> {
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        // Make sure `layout()` runs before the next frame is drawn.
        needsLayout = true
    }

    override func layout() {
        // After SwiftUI has applied the latest changes. If the window resizes, AppKit lays out again before drawing.
        super.layout()
        if let panel = window as? MenuPanel, panel.isVisible {
            // SwiftUI's ideal size. (`fittingSize` goes through Auto Layout, which can hold on to the current size.)
            panel.fit(intrinsicContentSize)
        }
    }
}
