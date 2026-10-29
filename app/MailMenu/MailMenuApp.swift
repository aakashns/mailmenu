import AppKit
import ServiceManagement
import SwiftUI

@main
enum MailMenuApp {
    static func main() {
        let delegate = AppDelegate()
        NSApplication.shared.delegate = delegate
        withExtendedLifetime(delegate) { NSApplication.shared.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !DemoMode.isEnabled {
            Self.enableOpenAtLoginOnFirstLaunch()
        }
        NSApp.mainMenu = Self.makeMainMenu()
        let menuBar = MenuBarController(model: AppModel())
        self.menuBar = menuBar
        // For development: `--open` shows the panel right away instead of waiting for a click on the icon.
        let arguments = ProcessInfo.processInfo.arguments
        if DemoMode.isEnabled, arguments.contains("--script") {
            DispatchQueue.main.async { menuBar.runDemoScript() }
        } else if arguments.contains("--open") {
            DispatchQueue.main.async { menuBar.open() }
        }
    }

    /// Registers the app as a login item once, so turning it off in System Settings > Login Items sticks.
    private static func enableOpenAtLoginOnFirstLaunch() {
        let key = "didRegisterLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? SMAppService.mainApp.register()
    }

    /// The menu bar is never shown (the app has no Dock icon), but its items give the panel ⌘Q and ⌘W.
    private static func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit Mail Menu", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(appItem)
        return mainMenu
    }
}

/// The envelope icon with the unread count next to it, drawn as a single template image: given a separate
/// icon and title, the menu bar positions them independently and the number ends up misaligned with the icon.
enum MenuBarIcon {
    static func image(unreadCount: Int) -> NSImage? {
        let envelope = Image(systemName: "envelope")
        let label = unreadCount > 0 ? Text("\(envelope) \(unreadCount)") : Text(envelope)
        let renderer = ImageRenderer(content: label
            .font(.system(size: NSFont.menuBarFont(ofSize: 0).pointSize))
            .foregroundStyle(.black))
        // Sharp on every connected display, not just the main one.
        renderer.scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        let image = renderer.nsImage
        // Template images are tinted by the system to match the menu bar's appearance.
        image?.isTemplate = true
        return image
    }
}
