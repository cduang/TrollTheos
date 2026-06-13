import Foundation

/// 网络加速配置（中国大陆 gh-proxy）
enum NetworkConfig {
    /// gh-proxy 前置代理前缀
    static let proxyPrefix = "https://v4.gh-proxy.org/"

    private static let proxyEnabledKey = "com.unjailtheos.isProxyEnabled"

    /// 加速模式开关（默认开启，适配国内网络）
    static var isProxyEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: proxyEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: proxyEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: proxyEnabledKey)
        }
    }

    /// 判断 URL 是否属于 GitHub 体系（需代理）
    static func isGitHubURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "github.com"
            || host == "www.github.com"
            || host == "raw.githubusercontent.com"
            || host == "codeload.github.com"
            || host == "api.github.com"
            || host.hasSuffix(".github.com")
    }

    /// 对 GitHub URL 应用 gh-proxy 前缀
    static func proxiedURL(_ url: URL) -> URL {
        guard isProxyEnabled, isGitHubURL(url) else { return url }
        return URL(string: proxiedURLString(url.absoluteString)) ?? url
    }

    /// 对 GitHub URL 字符串应用 gh-proxy 前缀
    static func proxiedURLString(_ urlString: String) -> String {
        guard isProxyEnabled else { return urlString }
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        // 已代理则跳过
        if trimmed.hasPrefix(proxyPrefix) { return trimmed }

        guard let url = URL(string: trimmed), isGitHubURL(url) else {
            return trimmed
        }

        // 示例: https://github.com/... → https://v4.gh-proxy.org/https://github.com/...
        return proxyPrefix + trimmed
    }
}
