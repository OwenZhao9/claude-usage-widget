import SwiftUI
import AppKit
import UsageCore

// MARK: - 颜色

extension UsageLevel {
    var color: Color {
        switch self {
        case .normal:   return Color(red: 0.04, green: 0.52, blue: 1.0)   // #0A84FF
        case .warning:  return Color(red: 1.0,  green: 0.62, blue: 0.04)  // #FF9F0A
        case .critical: return Color(red: 1.0,  green: 0.27, blue: 0.23)  // #FF453A
        }
    }
}

private func barColor(_ util: Double?) -> Color {
    guard let u = util else { return Color.white.opacity(0.28) }
    return UsageParsing.level(for: u).color
}

private func pct(_ util: Double?) -> String {
    guard let u = util else { return "—" }
    return "\(Int(u.rounded()))%"
}

// MARK: - 毛玻璃背景

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - 根视图

struct UsageRootView: View {
    @ObservedObject var store: UsageStore
    var onDesiredSize: (NSSize) -> Void
    var onQuit: () -> Void

    @State private var hovering = false

    enum Mode: Equatable { case compact, expanded, token }
    private var mode: Mode {
        // 调试用：WIDGET_FORCE=compact|expanded|token 固定形态，便于截图预览。
        switch ProcessInfo.processInfo.environment["WIDGET_FORCE"] {
        case "compact":  return .compact
        case "expanded": return .expanded
        case "token":    return .token
        default: break
        }
        if store.needsToken { return .token }
        return hovering ? .expanded : .compact
    }

    var body: some View {
        ZStack {
            VisualEffectBackground()
            // 深色 scrim：无论背后是亮网页还是白文档，都保持一致的深色玻璃观感、白字清晰。
            Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.55)
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { h in
            withAnimation(.easeOut(duration: 0.14)) { hovering = h }
        }
        .onAppear { emitSize() }
        .onChange(of: mode) { _ in emitSize() }
        .contextMenu {
            Button("刷新") { Task { await store.refresh() } }
            Button("粘贴新 token") { store.requestNewToken() }
            Divider()
            Button("退出") { onQuit() }
        }
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case .compact:  CompactRow(store: store)
        case .expanded: ExpandedView(store: store)
        case .token:    LoginPromptView(store: store)
        }
    }

    private func emitSize() {
        switch mode {
        case .compact:  onDesiredSize(UsagePanel.compactSize)
        case .expanded: onDesiredSize(UsagePanel.expandedSize)
        case .token:    onDesiredSize(UsagePanel.tokenSize)
        }
    }
}

// MARK: - 状态圆点

private func worstLevel(_ s: UsageSnapshot?) -> UsageLevel? {
    let utils = [s?.session?.utilization, s?.weekly?.utilization, s?.weeklyThird?.utilization].compactMap { $0 }
    guard let m = utils.max() else { return nil }
    return UsageParsing.level(for: m)
}

struct StatusDot: View {
    @ObservedObject var store: UsageStore
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
    }
    private var color: Color {
        switch store.state {
        case .offline:      return Color.white.opacity(0.3)
        case .unauthorized: return UsageLevel.critical.color
        default:            return worstLevel(store.snapshot)?.color ?? Color.white.opacity(0.3)
        }
    }
}

// MARK: - 紧凑行

struct CompactRow: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        HStack(spacing: 7) {
            StatusDot(store: store)
            if store.state == .unauthorized {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(UsageLevel.critical.color)
                    Text("token 失效")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.9))
                }
            } else {
                MiniSegment(util: store.snapshot?.session?.utilization)
                MiniSegment(util: store.snapshot?.weekly?.utilization)
                MiniSegment(util: store.snapshot?.weeklyThird?.utilization)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MiniSegment: View {
    let util: Double?
    var body: some View {
        HStack(spacing: 3) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16)).frame(width: 14, height: 4)
                Capsule().fill(barColor(util)).frame(width: 14 * fraction, height: 4)
            }
            Text(pct(util))
                .font(.system(size: 11, weight: .medium)).monospacedDigit()
                .foregroundColor(Color.white.opacity(0.92))
                .fixedSize(horizontal: true, vertical: false)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
    private var fraction: CGFloat { CGFloat(max(0, min(100, util ?? 0)) / 100) }
}

// MARK: - 展开视图

struct ExpandedView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FullRow(label: "当前会话", window: store.snapshot?.session)
            FullRow(label: "全模型（周）", window: store.snapshot?.weekly)
            FullRow(label: store.snapshot?.thirdLabel ?? "Fable（周）", window: store.snapshot?.weeklyThird)

            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)

            HStack {
                Text(footerText)
                    .font(.system(size: 10))
                    .foregroundColor(Color.white.opacity(0.5))
                Spacer()
                Button {
                    Task { await store.refresh() }
                } label: {
                    Text("刷新").font(.system(size: 10, weight: .medium))
                        .foregroundColor(UsageLevel.normal.color)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var footerText: String {
        switch store.state {
        case .loading where store.snapshot == nil:
            return "更新中…"
        case .offline:
            return "离线 · 上次 " + (store.lastUpdated.map(hhmm) ?? "—")
        default:
            let t = store.lastUpdated.map { "更新于 " + hhmm($0) } ?? ""
            return [t, planLabel].filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    private var planLabel: String {
        guard let raw = store.snapshot?.planLabel else { return "" }
        switch raw {
        case "default_claude_max_20x": return "Max 20x"
        case "default_claude_max_5x":  return "Max 5x"
        case "team":                   return "Team"
        case "enterprise":             return "Enterprise"
        case "pro":                    return "Pro"
        default:                       return raw
        }
    }

    private func hhmm(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }
}

struct FullRow: View {
    let label: String
    let window: UsageWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 11)).foregroundColor(Color.white.opacity(0.78))
                Spacer()
                Text(valueText)
                    .font(.system(size: 11, weight: .medium)).monospacedDigit()
                    .foregroundColor(Color.white.opacity(0.95))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14)).frame(height: 4)
                    Capsule().fill(barColor(window?.utilization))
                        .frame(width: geo.size.width * fraction, height: 4)
                }
            }
            .frame(height: 4)
        }
    }

    private var fraction: CGFloat { CGFloat(max(0, min(100, window?.utilization ?? 0)) / 100) }

    private var valueText: String {
        guard let w = window else { return "—" }
        return "\(pct(w.utilization)) · \(UsageParsing.countdown(to: w.resetsAt))"
    }
}

// MARK: - 登录引导

struct LoginPromptView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.state == .unauthorized ? "登录已失效" : "需要登录")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.white.opacity(0.92))
            Text("在项目目录运行下面这行，浏览器授权后自动完成：")
                .font(.system(size: 11))
                .foregroundColor(Color.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            Text("./login.sh")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.95))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.10)))

            HStack {
                Spacer()
                Button {
                    Task { store.needsToken = false; await store.refresh() }
                } label: {
                    Text("我已登录 · 刷新")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(UsageLevel.normal.color)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
