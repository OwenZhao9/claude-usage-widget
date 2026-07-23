import Foundation

/// 把浮窗自有的 OAuth 凭证存到本地文件（0600 权限）。
/// 之所以不用 Keychain：.app 是 ad-hoc 签名，每次重编身份都变，Keychain 会反复弹密码框；
/// 文件方式无弹窗、跨重编保留，token 仅当前用户可读。
public struct CredentialStore {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let u = fileURL {
            self.fileURL = u
        } else {
            let dir = FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/ClaudeUsageWidget", isDirectory: true)
            self.fileURL = dir.appendingPathComponent("credential.json")
        }
    }

    public var credential: OAuthCredential? {
        get { read() }
        nonmutating set {
            if let v = newValue { save(v) } else { delete() }
        }
    }

    private func read() -> OAuthCredential? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(OAuthCredential.self, from: data)
    }

    private func save(_ value: OAuthCredential) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: fileURL, options: .atomic)
        // 收紧权限：仅本人可读写。
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
