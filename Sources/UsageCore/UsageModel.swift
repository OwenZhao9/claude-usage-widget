import Foundation

/// 一档限流窗口的使用情况。
public struct UsageWindow: Equatable, Sendable {
    /// 已用百分比，0–100。
    public var utilization: Double
    /// 该窗口重置的时刻。
    public var resetsAt: Date

    public init(utilization: Double, resetsAt: Date) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

/// 一次拉取得到的完整额度快照。
public struct UsageSnapshot: Equatable, Sendable {
    /// 当前会话（five_hour）。
    public var session: UsageWindow?
    /// 全模型周限（seven_day）。
    public var weekly: UsageWindow?
    /// 第三档周限（seven_day_opus，账户界面上多显示为 Fable）。
    public var weeklyThird: UsageWindow?
    /// 第三档的展示名，若接口未给则由调用方回退。
    public var thirdLabel: String?
    /// 套餐名，如 "Max 20x"。
    public var planLabel: String?

    public init(
        session: UsageWindow? = nil,
        weekly: UsageWindow? = nil,
        weeklyThird: UsageWindow? = nil,
        thirdLabel: String? = nil,
        planLabel: String? = nil
    ) {
        self.session = session
        self.weekly = weekly
        self.weeklyThird = weeklyThird
        self.thirdLabel = thirdLabel
        self.planLabel = planLabel
    }

    /// 是否至少有一档有效数据。
    public var hasAny: Bool {
        session != nil || weekly != nil || weeklyThird != nil
    }
}

/// 进度条的告警级别，决定颜色。
public enum UsageLevel: String, Sendable {
    case normal   // 蓝
    case warning  // 橙
    case critical // 红
}
