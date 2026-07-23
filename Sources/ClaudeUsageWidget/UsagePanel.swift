import AppKit
import SwiftUI

/// 置顶、无边框、毛玻璃、可拖动的浮窗。托管 SwiftUI 内容，随悬停/token 状态改变尺寸。
final class UsagePanel: NSPanel {
    static let compactSize = NSSize(width: 176, height: 30)
    static let expandedSize = NSSize(width: 248, height: 148)
    static let tokenSize = NSSize(width: 264, height: 152)

    private let store: UsageStore
    private let posKey = "WidgetFrameOriginV1"

    init(store: UsageStore) {
        self.store = store
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.compactSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // 固定深色毛玻璃外观，与设计稿一致，且不受系统浅色模式影响（白字始终清晰）。
        appearance = NSAppearance(named: .darkAqua)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow

        let root = UsageRootView(
            store: store,
            onDesiredSize: { [weak self] size in self?.resize(to: size) },
            onQuit: { NSApp.terminate(nil) }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.autoresizingMask = [.width, .height]
        // 让 SwiftUI 的圆角/毛玻璃透出来。
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        contentView = hosting

        restorePosition()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 从左上角锚定改变尺寸，向下生长，保持在屏内。
    private func resize(to size: NSSize) {
        var f = frame
        guard f.size != size else { return }
        let topY = f.origin.y + f.size.height
        f.origin.y = topY - size.height
        f.size = size
        if let vf = screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            f.origin.x = min(max(f.origin.x, vf.minX), vf.maxX - size.width)
            f.origin.y = min(max(f.origin.y, vf.minY), vf.maxY - size.height)
        }
        setFrame(f, display: true, animate: true)
        invalidateShadow()
    }

    private func restorePosition() {
        let size = Self.compactSize
        var origin: NSPoint
        if let s = UserDefaults.standard.string(forKey: posKey) {
            origin = NSPointFromString(s)
        } else if let vf = NSScreen.main?.visibleFrame {
            origin = NSPoint(x: vf.maxX - size.width - 24, y: vf.maxY - size.height - 24) // 默认右上角
        } else {
            origin = NSPoint(x: 100, y: 100)
        }
        // 始终夹到屏内，避免旧的持久化位置（当时窗口更窄）把变宽后的窗口顶出屏幕。
        if let vf = screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX), vf.maxX - size.width)
            origin.y = min(max(origin.y, vf.minY), vf.maxY - size.height)
        }
        setFrameOrigin(origin)
    }

    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(point)
        UserDefaults.standard.set(NSStringFromPoint(point), forKey: posKey)
    }
}
