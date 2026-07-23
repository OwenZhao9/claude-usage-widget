import Foundation
import CryptoKit

/// 浮窗自有的 OAuth 凭证（与主登录隔离，含刷新所需字段）。
public struct OAuthCredential: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    /// 过期时刻，Unix 秒（跨语言可移植，Python 助手与 Swift 浮窗共用同一格式）。
    public var expiresAtEpoch: Double
    public var scopes: [String]

    public init(accessToken: String, refreshToken: String?, expiresAtEpoch: Double, scopes: [String]) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAtEpoch = expiresAtEpoch
        self.scopes = scopes
    }

    public var expiresAt: Date { Date(timeIntervalSince1970: expiresAtEpoch) }

    /// 提前 2 分钟视为过期，避免边界失败。
    public func isExpired(now: Date = Date()) -> Bool {
        expiresAtEpoch - now.timeIntervalSince1970 < 120
    }

    public var hasProfileScope: Bool { scopes.contains("user:profile") }
}

public enum OAuthError: Error {
    case badResponse(Int, String)
    case network(String)
    case decode
}

/// Claude OAuth：构造授权 URL（含 PKCE）、用授权码换 token、刷新 token。
/// 关键点：scope 显式包含 user:profile，否则打不了 /api/oauth/usage。
public struct OAuthClient: Sendable {
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    public static let authorizeURL = "https://claude.com/cai/oauth/authorize"
    public static let tokenURL = "https://api.anthropic.com/v1/oauth/token"
    public static let redirectURI = "https://platform.claude.com/oauth/code/callback"
    public static let scopes = ["user:inference", "user:profile"]

    public init() {}

    // MARK: - PKCE

    public struct PKCE: Sendable {
        public let verifier: String
        public let challenge: String
        public let state: String
    }

    public func makePKCE() -> PKCE {
        let verifier = Self.randomURLSafe(32)
        let state = Self.randomURLSafe(32)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Self.base64URL(Data(digest))
        return PKCE(verifier: verifier, challenge: challenge, state: state)
    }

    public func authorizeURL(pkce: PKCE) -> URL {
        var c = URLComponents(string: Self.authorizeURL)!
        c.queryItems = [
            .init(name: "code", value: "true"),
            .init(name: "client_id", value: Self.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "scope", value: Self.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: pkce.state),
        ]
        return c.url!
    }

    // MARK: - 授权码换 token

    /// 粘贴回来的可能是：纯 code、"code#state"、或整段回调 URL（含 ?code=…&state=…）。
    public func exchange(pastedCode raw: String, pkce: PKCE) async throws -> OAuthCredential {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var code = trimmed
        var state = pkce.state
        if trimmed.contains("code="), let comps = URLComponents(string: trimmed) {
            // 整段 URL：从 query 取 code / state。
            let items = comps.queryItems ?? []
            code = items.first(where: { $0.name == "code" })?.value ?? trimmed
            state = items.first(where: { $0.name == "state" })?.value ?? pkce.state
        } else {
            // 纯 code 或 code#state。
            let parts = trimmed.split(separator: "#", maxSplits: 1).map(String.init)
            code = parts.first ?? trimmed
            if parts.count > 1 { state = parts[1] }
        }
        let body: [String: Any] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": Self.clientID,
            "code_verifier": pkce.verifier,
            "state": state,
        ]
        return try await post(body)
    }

    // MARK: - 刷新

    public func refresh(refreshToken: String) async throws -> OAuthCredential {
        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
        ]
        return try await post(body)
    }

    // MARK: - 私有

    private func post(_ body: [String: Any]) async throws -> OAuthCredential {
        guard let url = URL(string: Self.tokenURL) else { throw OAuthError.network("bad url") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("ClaudeUsageWidget/1.0", forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data, resp: URLResponse
        do { (data, resp) = try await Net.session.data(for: req) }
        catch { throw OAuthError.network("\(error)") }

        guard let http = resp as? HTTPURLResponse else { throw OAuthError.network("no http") }
        let text = String(data: data, encoding: .utf8) ?? ""
        guard http.statusCode == 200 else { throw OAuthError.badResponse(http.statusCode, text) }

        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let access = obj["access_token"] as? String else { throw OAuthError.decode }
        let refresh = obj["refresh_token"] as? String
        let expiresIn = (obj["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        let scopeStr = (obj["scope"] as? String) ?? Self.scopes.joined(separator: " ")
        let scopes = scopeStr.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        return OAuthCredential(
            accessToken: access,
            refreshToken: refresh,
            expiresAtEpoch: Date().timeIntervalSince1970 + expiresIn,
            scopes: scopes
        )
    }

    // MARK: - 工具

    private static func randomURLSafe(_ n: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
