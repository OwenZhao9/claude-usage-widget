import Foundation

/// 共享的 URLSession：绕过系统代理直连。
/// 原因：用户开着系统代理（如 Shadowrocket），URLSession 默认走代理会连不上 api.anthropic.com，
/// 而直连（curl 那样）是通的。这里对这几个 API 调用强制直连。
public enum Net {
    public static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: 0,
            kCFNetworkProxiesHTTPSEnable as String: 0,
        ]
        c.timeoutIntervalForRequest = 15
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()
}
