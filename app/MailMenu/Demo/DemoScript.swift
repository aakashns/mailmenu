import AppKit

/// Walks through the actions most likely to upset the layout (deleting, failing, collapsing, switching filters,
/// signing out and in) against the fake server, then quits. Launch with `--demo --script` (see `scripts/demo.sh`).
///
/// It saves a snapshot of the panel after each step, and after every frame drawn it checks that the window is
/// exactly the size of its content: a mismatch is a frame where the content is clipped or floats in a too-big window.
@MainActor
final class DemoScript {
    private let model: AppModel
    private let panel: MenuPanel
    private let directory = URL(filePath: NSTemporaryDirectory()).appending(path: "MailMenuDemo")
    private var framesChecked = 0
    private var mismatches: [String] = []
    private var step = "launch"

    init(model: AppModel, panel: MenuPanel) {
        self.model = model
        self.panel = panel
    }

    func run() async {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, .max) { _, _ in
            MainActor.assumeIsolated { self.checkFrame() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)

        await settle()
        snapshot("open")

        let work = model.accounts[0]
        let first = work.visibleMessages.first!
        let deleting = Task { await model.delete(first, in: work) }
        try? await Task.sleep(for: .milliseconds(100))
        snapshot("deleting")
        await deleting.value
        await settle()
        snapshot("deleted")

        let flaky = work.visibleMessages.first { $0.senderEmail == DemoData.failingSender }!
        await model.archive(flaky, in: work)
        await settle()
        snapshot("archive-failed")

        // These change the panel's height.
        work.isExpanded = false
        await settle()
        snapshot("collapsed")

        let personal = model.accounts[1]
        await model.delete(personal.visibleMessages.first!, in: personal)
        await settle()
        snapshot("deleted-in-short-list")

        work.isExpanded = true
        await settle()
        snapshot("expanded")

        model.mailFilter = .all
        await settle()
        let countBefore = work.visibleMessages.count
        let rapid = work.visibleMessages.prefix(3).map { message in Task { await model.delete(message, in: work) } }
        try? await Task.sleep(for: .milliseconds(100))
        let countDuring = work.visibleMessages.count
        for task in rapid { await task.value }
        await settle()
        snapshot("all-after-3-deletes")
        log("All filter: \(countBefore) rows before deleting 3, \(countDuring) right after (spares move up), \(work.visibleMessages.count) after refresh")

        model.signOut(model.accounts[1])
        await settle()
        snapshot("signed-out")

        await model.addAccount()
        await settle()
        snapshot("added-account")

        CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        log("Checked \(framesChecked) frames, \(mismatches.count) where the window and content sizes differed")
        mismatches.prefix(20).forEach { log("  \($0)") }
        log("Snapshots: \(directory.path())")
        NSApp.terminate(nil)
    }

    private func checkFrame() {
        guard panel.isVisible else { return }
        framesChecked += 1
        let content = panel.laidOutContentSize
        if content != panel.frame.size {
            mismatches.append("\(step): window \(panel.frame.size), content \(content)")
        }
    }

    /// Waits until nothing is loading.
    private func settle() async {
        repeat {
            try? await Task.sleep(for: .milliseconds(200))
        } while model.isSigningIn || model.accounts.contains { $0.isRefreshing || !$0.hasLoaded }
        try? await Task.sleep(for: .milliseconds(200))
    }

    private var snapshotCount = 0

    private func snapshot(_ name: String) {
        step = name
        snapshotCount += 1
        let url = directory.appending(path: String(format: "%02d-%@.png", snapshotCount, name))
        guard let data = panel.snapshot() else { return }
        try? data.write(to: url)
        log("\(name): panel \(Int(panel.frame.width))×\(Int(panel.frame.height))")
    }

    private func log(_ message: String) {
        print(message)
        fflush(stdout)
    }
}
