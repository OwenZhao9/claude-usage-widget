import Foundation
import Security

/// 浮窗专用 token 的 Keychain 读写。与 Claude Code 主凭证隔离（独立 service）。
public struct TokenStore {
    public let service: String
    public let account: String

    public init(service: String = "com.local.claude-usage-widget", account: String = "oauth-token") {
        self.service = service
        self.account = account
    }

    public var token: String? {
        get { read() }
        nonmutating set {
            if let v = newValue, !v.isEmpty { save(v) } else { delete() }
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func read() -> String? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save(_ value: String) {
        SecItemDelete(baseQuery as CFDictionary)
        var add = baseQuery
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
