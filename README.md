# Claude 额度浮窗

一个 macOS 桌面**置顶毛玻璃浮窗**，实时显示 Claude 订阅额度。平时是超紧凑一行（三个迷你进度条 + 百分比），鼠标悬停展开成完整三条（当前会话 / 全模型周 / Fable 周，各带重置倒计时）。

## 构建 + 运行

```bash
./build.sh              # 编译 release 并打包成「Claude 额度.app」（含 ad-hoc 签名）
./login.sh              # 首次登录：浏览器 OAuth 授权（见下），凭证存到本地
open "Claude 额度.app"   # 启动浮窗
```

需要 Swift 6 工具链（Command Line Tools 即可，无需完整 Xcode）。

## 登录（关键）

浮窗需要一个带 `user:profile` 权限的 OAuth 凭证才能读额度接口。

> ⚠️ 注意：`claude setup-token` 生成的 token **只有 `user:inference` 权限，打不了额度接口**。必须用下面的登录流程（它显式请求了 `user:profile`）。

```bash
./login.sh
```

会打开浏览器到 Claude 授权页（勾选项里有「Access your Anthropic profile information」），点 **Authorize**，把回调页地址里的 `code=` 值粘回终端即可。凭证（含刷新 token）存到：

```
~/Library/Application Support/ClaudeUsageWidget/credential.json   (0600)
```

浮窗会用刷新 token 自动续期（access token 有效期 8 小时）。凭证彻底失效后，浮窗变红、右键「粘贴新 token」或重跑 `./login.sh`。

**为什么用文件不用 Keychain**：`.app` 是 ad-hoc 签名，每次重编身份都变，Keychain 会反复弹密码框。文件（仅本人可读）无弹窗、跨重编保留。

## 交互

- **悬停**：展开完整三条 + 重置倒计时。
- **拖动**：按住浮窗任意处拖动，位置自动记忆。
- **右键**：刷新 / 粘贴新 token / 退出。
- **颜色**：`<75%` 蓝、`75–90%` 橙、`>90%` 红；状态圆点取三档里最差的。

## 开机自启（可选）

系统设置 →「通用」→「登录项」→ 加号，选「Claude 额度.app」。

## 数据来源

`GET https://api.anthropic.com/api/oauth/usage`（Bearer token + `anthropic-beta: oauth-2025-04-20`），默认每 60 秒刷新。响应里的 `limits` 数组给出三档：`session` / `weekly_all` / `weekly_scoped`（后者的 `scope.model.display_name` 就是 "Fable"）。`resets_at` 是 ISO-8601 字符串。

> 网络：浮窗的 URLSession **强制直连、绕过系统代理**（Shadowrocket 之类会让 URLSession 连不上 api.anthropic.com，而直连是通的）。见 `Sources/UsageCore/Net.swift`。

## 开发

```bash
swift run SelfTest                              # 纯逻辑单测（解析 / 倒计时 / 阈值 / ISO 日期）
WIDGET_DEMO=1 WIDGET_FORCE=expanded \
  .build/debug/ClaudeUsageWidget                # 假数据预览 UI（compact|expanded|token）
WIDGET_TOKEN=<access_token> swift run Probe     # 打一次接口，dump 原始 JSON + 解析结果
swift run Login                                 # 走 OAuth 登录（= ./login.sh）
```

### 结构

```
Sources/
  UsageCore/           纯逻辑库（可测）：模型 / 解析 / 网络 / OAuth / 凭证存储
    OAuth.swift          授权 URL + PKCE + 换 token + 刷新
    UsageParsing.swift   limits 数组 / ISO 日期 / 阈值 / 倒计时（纯函数）
    UsageClient.swift    调 /api/oauth/usage
    CredentialStore.swift 本地文件存凭证（0600）
    Net.swift            绕过系统代理的 URLSession
  ClaudeUsageWidget/   GUI：置顶面板 + SwiftUI 视图 + 状态 store（含自动刷新）
  SelfTest/            无 XCTest 环境下的断言自测
  Probe/ Login/        诊断 / 登录助手
docs/superpowers/specs/ 设计文档 + 实现记录
```
