import AppKit

@main
@MainActor
struct AppEntry {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // accessory：无 Dock 图标、不进 App 切换器（等价 LSUIElement）。
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
