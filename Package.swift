// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeUsageWidget",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "UsageCore"
        ),
        .executableTarget(
            name: "ClaudeUsageWidget",
            dependencies: ["UsageCore"]
        ),
        // 纯 Command Line Tools 环境下无 XCTest，故用独立可执行做自测。
        // 运行：swift run SelfTest
        .executableTarget(
            name: "SelfTest",
            dependencies: ["UsageCore"]
        ),
        // 诊断：拿真 token 打一次接口，dump 原始 JSON + 解析结果（输出不含 token）。
        // 运行：WIDGET_TOKEN=sk-ant-oat01-… swift run Probe
        .executableTarget(
            name: "Probe",
            dependencies: ["UsageCore"]
        ),
        // 登录助手：OAuth 授权（含 user:profile），凭证存进浮窗 Keychain。
        // 运行：swift run Login
        .executableTarget(
            name: "Login",
            dependencies: ["UsageCore"]
        ),
    ]
)
