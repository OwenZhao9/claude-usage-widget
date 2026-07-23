import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: UsagePanel!
    private let store = UsageStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = UsagePanel(store: store)
        panel.orderFrontRegardless()
        store.start()
        // 首次无 token 时，激活应用并让面板成为 key，以便粘贴框接收键盘输入。
        if store.needsToken {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
