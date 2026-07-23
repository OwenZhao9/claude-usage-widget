# Claude 额度浮窗 — 设计文档

日期：2026-07-23
状态：已批准，实现中

## 目标

一个 macOS 桌面**置顶浮窗**，实时显示当前 Claude Code 订阅额度的使用百分比。平时以**超紧凑一行**呈现（三个迷你进度条 + 百分比数字），鼠标悬停展开成完整三条信息（带各自的重置倒计时）。

## 数据来源

- 端点：`GET https://api.anthropic.com/api/oauth/usage`
- 请求头：
  - `Authorization: Bearer <token>`
  - `anthropic-beta: oauth-2025-04-20`
  - `Content-Type: application/json`
  - `User-Agent: <自定义>`
- 超时：5 秒
- 返回：JSON body，含三档限流窗口。每个窗口形如 `{ utilization: 0-100, resets_at: <unix 秒> }`。
  - 候选键：`five_hour`（当前会话）、`seven_day`（全模型 / 周）、`seven_day_opus`（Fable / 周）。
  - 实际键的确切拼写在实现首步用真 token 联网 dump 一次坐实。

> 注：普通推理请求的响应头 `anthropic-ratelimit-unified-{5h,7d}-utilization/-reset` 也带限流信息，但只有 5h/7d 两档、无第三档，且需发起推理调用，故不采用。`/api/oauth/usage` 一次拿全。

## 认证

- 浮窗使用 `claude setup-token` 生成的**长期专用 token**，与 Claude Code / 桌面端主凭证完全隔离，互不干扰。
- 存储：写入浮窗专属 Keychain 项（service `com.local.claude-usage-widget`，account `oauth-token`）。`.app` 在 build 时 ad-hoc 签名，让 Keychain 访问稳定。
- 首次启动若无 token → 浮窗内显示一个粘贴框，提示运行 `claude setup-token` 并粘贴。
- token 失效（接口 401）→ 紧凑行变红色叹号，点击可重新粘贴。

## 架构

Swift Package，两个源码目标 + 一个测试目标：

```
Package.swift
Sources/
  UsageCore/            纯逻辑库（可测）
    UsageModel.swift      数据模型 UsageWindow / UsageSnapshot
    UsageParsing.swift    JSON 解析、倒计时格式化、颜色阈值（纯函数）
    UsageClient.swift     URLSession 调接口
    TokenStore.swift      Keychain 读写
  ClaudeUsageWidget/    GUI 可执行（依赖 UsageCore）
    main.swift            NSApplication 启动
    AppDelegate.swift     建 panel、菜单、定时器
    UsagePanel.swift      NSPanel 子类（置顶、无边框、毛玻璃、可拖动）
    UsageView.swift       SwiftUI：紧凑行 + 悬停展开 + 粘贴框
    UsageStore.swift      ObservableObject，驱动 UI 刷新
Tests/
  UsageCoreTests/         解析 / 格式化 / 阈值单测
build.sh                拿 swift build 产物组装 .app + ad-hoc 签名
```

### 数据流

`Timer 每 60s`（或手动刷新）→ `UsageClient.fetch()` 带 Bearer token → `UsageParsing.parse()` → `UsageSnapshot` → `UsageStore`（@Published）→ SwiftUI 刷新。

## 窗口行为

- `NSPanel`，`level = .floating`，`.nonactivatingPanel | .borderless`，不抢应用焦点。
- `canBecomeKey = true`（让粘贴框能接收键盘输入）。
- 毛玻璃：`NSVisualEffectView`（`.hudWindow`），圆角，`backgroundColor = .clear`、`isOpaque = false`、`hasShadow = true`。
- 可拖动：`isMovableByWindowBackground = true`。
- 位置记忆：存 `UserDefaults`。
- 出现在所有空间、随桌面切换保持：`collectionBehavior = [.canJoinAllSpaces, .stationary]`。
- `LSUIElement = true`：无 Dock 图标、不占 App 切换器。

## 交互

- **平时**：紧凑一行 ≈190×34，三组「迷你进度条 + 百分比」，前面一个圆点表示整体状态。
- **悬停**：动画展开到 ≈260×150，三条完整信息（标签 / 百分比 / 重置倒计时）+ 底部「刚刚更新 · 套餐名」和「刷新」。左上角锚定，向下生长。
- **右键菜单**：刷新、粘贴新 token、开机自启开关、退出。
- **颜色阈值**：`<75%` 蓝、`75–90%` 橙、`>90%` 红。会话/全模型/Fable 各自独立着色。

## 倒计时格式

`resets_at`（unix 秒）− now：`>24h → "Nd Nh"`；`1–24h → "Nh Nm"`；`<1h → "Nm"`。

## 错误处理

- 网络失败 / 超时：保留上一次数据，圆点转灰，底部显示「离线 · 上次 HH:mm」；下个周期重试。
- 401（token 失效）：紧凑行变红叹号，悬停提示「token 失效，点击重新粘贴」。
- JSON 结构异常：容错解析，缺失的窗口对应进度条置灰，不崩溃。
- 首次无 token：显示粘贴引导。

## 非目标（YAGNI）

- 不做历史曲线 / 通知 / 多账号。
- 不做偏好设置窗口（阈值、刷新间隔先硬编码，后续需要再加）。

---

## 实现记录（实现中发现，与初始设计的偏差）

实现时联网实测推翻了几处初始假设，最终方案如下：

1. **认证：不能用 `claude setup-token`。** 它生成的 token 只有 `user:inference` 权限，而 `/api/oauth/usage` 要求 `user:profile`，返回 `permission_error`。主登录凭证有 `user:profile`，但本机是在 Claude 桌面端里跑（`CLAUDE_CODE_ENTRYPOINT=claude-desktop`），auth 由宿主在内存管理，Keychain 里的 CLI 凭证已过期且 refresh token 失效。
   → **改为浮窗自建 OAuth 授权流**：复用 Claude Code 的 client_id `9d1c250a-…`，授权 URL 显式请求 `scope=user:inference user:profile`（PKCE + 手动 code 回传），换到带 `user:profile` 的可刷新凭证。这反而同时满足了「与主登录隔离」的初衷。登录助手见 `Sources/Login`，`./login.sh`。
   - 授权：`https://claude.com/cai/oauth/authorize`（307 到 claude.ai）；换 token / 刷新：`POST https://api.anthropic.com/v1/oauth/token`；redirect_uri `https://platform.claude.com/oauth/code/callback`。

2. **响应结构与初始猜测不同。** 三档不在 `seven_day_opus`（该字段为 null），而在 `limits` 数组：`kind = session | weekly_all | weekly_scoped`，字段 `percent` / `severity` / `resets_at` / `scope`。第三档标签取 `scope.model.display_name`（"Fable"）。`resets_at` 是 **ISO-8601 字符串**（含微秒 + 时区），不是 unix 秒。解析器优先用 `limits`，回退顶层对象。

3. **凭证存文件而非 Keychain。** `.app` 是 ad-hoc 签名，身份每次重编都变，Keychain 会反复弹密码授权框。改存 `~/Library/Application Support/ClaudeUsageWidget/credential.json`（0600）。

4. **URLSession 必须绕过系统代理。** 用户开着 Shadowrocket，URLSession 默认走系统代理连不上 api.anthropic.com（curl 直连可通）。`Net.swift` 里强制 `connectionProxyDictionary` 关闭代理直连。

5. **无 XCTest。** 纯 Command Line Tools 下 `swift test` 缺 XCTest 模块，改用独立可执行 `SelfTest` 做断言自测。

6. **套餐名**从 `~/.claude.json` 的 `oauthAccount.organizationRateLimitTier` 读（如 `default_claude_max_20x` → "Max 20x"），接口本身不返回。
