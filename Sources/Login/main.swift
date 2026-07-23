import Foundation
import UsageCore
import AppKit

// 浮窗登录助手：走 OAuth 授权（请求 user:profile 权限），把凭证存进浮窗 Keychain。
// 用法：swift run Login   然后在浏览器授权、把 code 粘回来。

let oauth = OAuthClient()
let pkce = oauth.makePKCE()
let url = oauth.authorizeURL(pkce: pkce)

print("▸ 即将打开浏览器授权（请求 scope：\(OAuthClient.scopes.joined(separator: " "))）")
print("  若没自动打开，手动访问：\n  \(url.absoluteString)\n")
NSWorkspace.shared.open(url)

print("""
点 Authorize 后，浏览器会跳到 platform.claude.com/oauth/code/callback?code=…（页面可能因代理打不开，没关系）。
从地址栏复制整段回调地址、或只复制 code= 后面那串，粘到这里回车：
""")
guard let line = readLine(strippingNewline: true), !line.trimmingCharacters(in: .whitespaces).isEmpty else {
    FileHandle.standardError.write(Data("未输入 code。\n".utf8)); exit(2)
}

let sem = DispatchSemaphore(value: 0)
var exitCode: Int32 = 0

Task {
    defer { sem.signal() }
    do {
        let cred = try await oauth.exchange(pastedCode: line, pkce: pkce)
        print("\n✅ 拿到凭证。scope：\(cred.scopes.joined(separator: " "))")
        print("   有 user:profile：\(cred.hasProfileScope ? "是" : "否 ⚠️")")

        // 自检：立刻打一次 usage
        let data = try await UsageClient().fetch(token: cred.accessToken)
        let snap = UsageParsing.parse(data)
        if snap.hasAny {
            print("   usage 自检：会话 \(snap.session?.utilization.description ?? "-")% / 周 \(snap.weekly?.utilization.description ?? "-")% / 三档 \(snap.weeklyThird?.utilization.description ?? "-")%")
            CredentialStore().credential = cred
            print("   已存入 Keychain。可以启动浮窗了。")
        } else {
            print("   ⚠️ usage 返回但解析为空，dump 原始：")
            print(String(data: data, encoding: .utf8) ?? "<非文本>")
            CredentialStore().credential = cred
        }
    } catch let OAuthError.badResponse(code, body) {
        FileHandle.standardError.write(Data("交换失败 \(code)：\(body)\n".utf8)); exitCode = 1
    } catch {
        FileHandle.standardError.write(Data("失败：\(error)\n".utf8)); exitCode = 1
    }
}

sem.wait()
exit(exitCode)
