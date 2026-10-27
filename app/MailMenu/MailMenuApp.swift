import AppKit
import SwiftUI

@main
struct MailMenuApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environment(model)
        } label: {
            MenuBarLabel(unreadCount: model.totalUnreadCount)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The envelope icon with the unread count next to it.
///
/// Drawn as a single template image: given a separate icon and title, the menu bar positions
/// them independently and the number ends up misaligned with the icon.
private struct MenuBarLabel: View {
    let unreadCount: Int

    var body: some View {
        if let image = Self.render(unreadCount) {
            Image(nsImage: image)
                .accessibilityLabel(unreadCount > 0 ? "\(unreadCount) unread" : "Mail Menu")
        } else {
            Image(systemName: "envelope")
        }
    }

    private static func render(_ count: Int) -> NSImage? {
        let envelope = Image(systemName: "envelope")
        let label = count > 0 ? Text("\(envelope) \(count)") : Text(envelope)
        let renderer = ImageRenderer(content: label
            .font(.system(size: NSFont.menuBarFont(ofSize: 0).pointSize))
            .foregroundStyle(.black))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage
        // Template images are tinted by the system to match the menu bar's appearance.
        image?.isTemplate = true
        return image
    }
}
