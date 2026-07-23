import Foundation

public enum UsageClientError: Error, Equatable {
    case unauthorized
    case http(Int)
    case network
    case badURL
}

/// 调 `/api/oauth/usage` 拉原始 JSON。解析交给 `UsageParsing`。
public struct UsageClient: Sendable {
    public static let endpoint = "https://api.anthropic.com/api/oauth/usage"
    public static let betaHeader = "oauth-2025-04-20"

    public init() {}

    /// 拉取原始响应体。失败按语义抛 `UsageClientError`。
    public func fetch(token: String) async throws -> Data {
        guard let url = URL(string: Self.endpoint) else { throw UsageClientError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 8
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("ClaudeUsageWidget/1.0 (macOS)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await Net.session.data(for: req)
        } catch {
            throw UsageClientError.network
        }
        guard let http = resp as? HTTPURLResponse else { throw UsageClientError.network }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            throw UsageClientError.unauthorized
        default:
            throw UsageClientError.http(http.statusCode)
        }
    }
}
