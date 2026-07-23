import Foundation

/// 纯函数集合：JSON 解析、倒计时格式化、颜色阈值。无副作用，便于单测。
public enum UsageParsing {

    // MARK: - 阈值

    /// 根据百分比给出告警级别。<75 正常，75–90 警告，>90 严重。
    public static func level(for utilization: Double) -> UsageLevel {
        switch utilization {
        case ..<75: return .normal
        case ..<90: return .warning
        default: return .critical
        }
    }

    // MARK: - 倒计时格式化

    /// 把「到 resetsAt 还剩多久」格式化成紧凑字符串。
    /// >24h → "Nd Nh"；1–24h → "Nh Nm"；<1h → "Nm"；已过 → "现在"。
    public static func countdown(to resetsAt: Date, now: Date = Date()) -> String {
        let secs = Int(resetsAt.timeIntervalSince(now).rounded())
        if secs <= 0 { return "现在" }
        let m = secs / 60
        let mins = m % 60
        let hours = (m / 60) % 24
        let days = m / (60 * 24)
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    // MARK: - JSON 解析

    /// 从 `/api/oauth/usage` 的响应体解析出快照。容错：结构不符时尽力提取，缺失的窗口置 nil。
    public static func parse(_ data: Data, now: Date = Date()) -> UsageSnapshot {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return UsageSnapshot()
        }
        return parse(root, now: now)
    }

    /// 供测试直接传字典。优先用结构化的 `limits` 数组，回退到顶层窗口对象。
    public static func parse(_ root: [String: Any], now: Date = Date()) -> UsageSnapshot {
        var session: UsageWindow?
        var weekly: UsageWindow?
        var third: UsageWindow?
        var thirdLabel: String?

        // 首选：limits 数组（含第三档的 display_name，如 "Fable"）。
        if let limits = root["limits"] as? [[String: Any]] {
            for l in limits {
                guard let pct = number(l, ["percent", "utilization", "used_percentage"]) else { continue }
                let date = parseDate(l["resets_at"]) ?? .distantFuture
                let w = UsageWindow(utilization: pct, resetsAt: date)
                switch l["kind"] as? String {
                case "session":
                    session = session ?? w
                case "weekly_all":
                    weekly = weekly ?? w
                case "weekly_scoped":
                    if third == nil {
                        third = w
                        if let scope = l["scope"] as? [String: Any],
                           let model = scope["model"] as? [String: Any],
                           let name = model["display_name"] as? String {
                            thirdLabel = name
                        }
                    }
                default:
                    break
                }
            }
        }

        // 回退：顶层窗口对象（五小时 / 七天 / opus / sonnet）。
        let container = firstDict(root, ["rate_limits", "usage"]) ?? root
        if session == nil { session = windowObject(container["five_hour"]) }
        if weekly == nil { weekly = windowObject(container["seven_day"]) }
        if third == nil {
            third = windowObject(container["seven_day_opus"]) ?? windowObject(container["seven_day_sonnet"])
        }

        let plan = string(root, ["plan", "plan_name", "subscription_type", "rate_limit_tier"])
        return UsageSnapshot(
            session: session,
            weekly: weekly,
            weeklyThird: third,
            thirdLabel: thirdLabel,
            planLabel: plan
        )
    }

    // MARK: - 私有辅助

    /// 解析 {utilization/used_percentage, resets_at} 形式的窗口对象。
    private static func windowObject(_ any: Any?) -> UsageWindow? {
        guard let obj = any as? [String: Any],
              let util = number(obj, ["utilization", "used_percentage", "percentage", "percent"]) else { return nil }
        let date = parseDate(obj["resets_at"]) ?? parseDate(obj["reset"]) ?? .distantFuture
        return UsageWindow(utilization: util, resetsAt: date)
    }

    /// resets_at 可能是 ISO-8601 字符串（含微秒 + 时区）或 unix 秒。
    public static func parseDate(_ any: Any?) -> Date? {
        if let n = any as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue) }
        if let d = any as? Double { return Date(timeIntervalSince1970: d) }
        guard let s = any as? String, !s.isEmpty else { return nil }
        if let d = Double(s) { return Date(timeIntervalSince1970: d) }
        // 去掉小数秒（ISO8601DateFormatter 对 6 位微秒不稳），再解析。
        let stripped = s.replacingOccurrences(
            of: #"\.\d+"#, with: "", options: .regularExpression)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: stripped) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    private static func firstDict(_ root: [String: Any], _ keys: [String]) -> [String: Any]? {
        for k in keys { if let d = root[k] as? [String: Any] { return d } }
        return nil
    }

    private static func number(_ obj: [String: Any], _ keys: [String]) -> Double? {
        for k in keys {
            if let n = obj[k] as? NSNumber { return n.doubleValue }
            if let d = obj[k] as? Double { return d }
            if let i = obj[k] as? Int { return Double(i) }
            if let s = obj[k] as? String, let d = Double(s) { return d }
        }
        return nil
    }

    private static func string(_ obj: [String: Any], _ keys: [String]) -> String? {
        for k in keys { if let s = obj[k] as? String, !s.isEmpty { return s } }
        return nil
    }
}
