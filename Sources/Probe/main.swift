import Foundation
import UsageCore

// 诊断工具：拿 token 打一次 /api/oauth/usage，打印原始 JSON 与解析结果。
// token 来源优先级：命令行参数 > 环境变量 WIDGET_TOKEN > 浮窗 Keychain。
// 输出只含接口返回的 JSON（无 token），可安全粘贴给他人核对结构。

let token: String? = {
    if CommandLine.arguments.count > 1 { return CommandLine.arguments[1] }
    if let e = ProcessInfo.processInfo.environment["WIDGET_TOKEN"], !e.isEmpty { return e }
    return TokenStore().token
}()

guard let token, !token.isEmpty else {
    FileHandle.standardError.write(Data("未提供 token。用法：WIDGET_TOKEN=sk-ant-oat01-… swift run Probe\n".utf8))
    exit(2)
}

let sem = DispatchSemaphore(value: 0)
var code: Int32 = 0

Task {
    defer { sem.signal() }
    do {
        let data = try await UsageClient().fetch(token: token)
        print("=== 原始 JSON（无 token） ===")
        if let obj = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let s = String(data: pretty, encoding: .utf8) {
            print(s)
        } else {
            print(String(data: data, encoding: .utf8) ?? "<非文本>")
        }
        let snap = UsageParsing.parse(data)
        print("\n=== 解析结果 ===")
        print("会话 five_hour      :", snap.session.map { "\($0.utilization)% reset \($0.resetsAt)" } ?? "nil ⚠️")
        print("全模型 seven_day    :", snap.weekly.map { "\($0.utilization)% reset \($0.resetsAt)" } ?? "nil ⚠️")
        print("第三档 opus/fable   :", snap.weeklyThird.map { "\($0.utilization)% reset \($0.resetsAt)" } ?? "nil ⚠️")
        print("套餐 plan           :", snap.planLabel ?? "nil")
    } catch UsageClientError.unauthorized {
        FileHandle.standardError.write(Data("401/403：token 无效或无权限。\n".utf8))
        code = 1
    } catch {
        FileHandle.standardError.write(Data("请求失败：\(error)\n".utf8))
        code = 1
    }
}

sem.wait()
exit(code)
