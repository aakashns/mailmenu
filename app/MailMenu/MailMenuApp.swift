import SwiftUI

@main
struct MailMenuApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Mail Menu", systemImage: "envelope") {
            MenuContentView()
                .environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}
