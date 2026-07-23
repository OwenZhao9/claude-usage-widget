import Foundation
import Combine
import UsageCore

/// 驱动 UI 的可观察状态。持有定时器、网络、OAuth 凭证（自动刷新）。
@MainActor
final class UsageStore: ObservableObject {
    enum LoadState: Equatable { case idle, loading, ok, offline, unauthorized }

    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var lastUpdated: Date?
    @Published var needsToken: Bool = false

    let refreshInterval: TimeInterval = 60
    private var timer: Timer?
    private let client = UsageClient()
    private let oauth = OAuthClient()
    private let credStore = CredentialStore()

    /// 启动首刷 + 周期刷新。
    func start() {
        if ProcessInfo.processInfo.environment["WIDGET_DEMO"] == "1" {
            let now = Date()
            snapshot = UsageSnapshot(
                session: UsageWindow(utilization: 69, resetsAt: now.addingTimeInterval(2*3600 + 14*60)),
                weekly: UsageWindow(utilization: 89, resetsAt: now.addingTimeInterval(6*3600 + 54*60)),
                weeklyThird: UsageWindow(utilization: 62, resetsAt: now.addingTimeInterval(6*3600 + 54*60)),
                thirdLabel: "Fable（周）",
                planLabel: "default_claude_max_20x"
            )
            lastUpdated = now
            state = .ok
            needsToken = false
            return
        }
        needsToken = (credStore.credential == nil)
        Task { await refresh() }
        let t = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 请求重新登录（清掉现有凭证，显示引导）。
    func requestNewToken() {
        credStore.credential = nil
        needsToken = true
    }

    var hasCredential: Bool { credStore.credential != nil }

    func refresh() async {
        guard var cred = credStore.credential else {
            needsToken = true
            return
        }
        if state != .ok { state = .loading }

        // 到期前主动刷新。
        if cred.isExpired(), let rt = cred.refreshToken {
            if let fresh = try? await oauth.refresh(refreshToken: rt) {
                cred = fresh
                credStore.credential = fresh
            }
        }

        do {
            let data = try await client.fetch(token: cred.accessToken)
            apply(data)
            needsToken = false
        } catch UsageClientError.unauthorized {
            // 401 兜底：再刷新一次重试。
            if let rt = cred.refreshToken,
               let fresh = try? await oauth.refresh(refreshToken: rt) {
                credStore.credential = fresh
                if let data = try? await client.fetch(token: fresh.accessToken) {
                    apply(data)
                    needsToken = false
                    return
                }
            }
            state = .unauthorized
            needsToken = true
        } catch {
            state = .offline
        }
    }

    private func apply(_ data: Data) {
        var snap = UsageParsing.parse(data)
        if snap.planLabel == nil { snap.planLabel = Self.readPlanTier() }
        snapshot = snap
        lastUpdated = Date()
        state = .ok
    }

    /// 从 ~/.claude.json 读套餐等级（如 default_claude_max_20x），仅作页脚展示。
    private static func readPlanTier() -> String? {
        let path = ("~/.claude.json" as NSString).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let acct = obj["oauthAccount"] as? [String: Any],
              let tier = acct["organizationRateLimitTier"] as? String else { return nil }
        return tier
    }
}
