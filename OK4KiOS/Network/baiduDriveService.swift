import Foundation

// MARK: - 百度网盘网络层
//
// 端点取证来源：Docs/NetdiskEndpointsEvidence.md 百度小节 + Docs/baidu-strings.txt / Docs/baidu-calls.txt
// Android 核心委托 C0243g + W0/A 类，登录方式：扫码登录 K2(17) + 手动 Cookie (r1)
// 存储方式：Cookie 持久化（非 OAuth token）
//
// 注意：扫码/轮询端点无法从 smali 完整取证，本文件仅实现 Cookie 手动登录所需的
// 网络请求（用户信息获取），扫码相关端点诚实保留 pending（抛 FishDriveError.protocolPending）。

// MARK: - 百度网盘凭据（Cookie 持久化）

struct BaiduCredential: Equatable, Sendable {
    let raw: Data
    let cookies: [String: String]
    let username: String
    let avatar: String
    let vipLevel: String

    var displayName: String? {
        username.nonempty
    }

    init(responseData: Data, fallback: BaiduCredential? = nil) throws {
        let response = try Self.dictionary(responseData)
        let previous = try fallback.map { try Self.dictionary($0.raw) } ?? [:]
        var merged = Self.deepMerge(previous, response)

        // 百度返回的用户信息字段（从 baidu-strings.txt 取证）
        let responseDataObject = response["data"] as? [String: Any] ?? response
        let previousDataObject = previous["data"] as? [String: Any] ?? previous

        func value(_ keys: [String], fallbackValue: String = "") -> String {
            Self.firstString(in: [responseDataObject, response, previousDataObject, previous], keys: keys) ?? fallbackValue
        }

        // Cookie 从请求头或响应中提取
        var cookieDict: [String: String] = [:]
        let cookieString = value(["cookie", "Cookie"])
        if !cookieString.isEmpty {
            for pair in cookieString.split(separator: ";") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    cookieDict[String(parts[0]).trimmingCharacters(in: .whitespaces)] = String(parts[1]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        // 也支持直接传入 cookie 字典
        if let cookieObj = responseDataObject["cookies"] as? [String: String] {
            cookieDict.merge(cookieObj) { _, new in new }
        }
        if let cookieObj = previousDataObject["cookies"] as? [String: String] {
            cookieDict.merge(cookieObj) { _, new in new }
        }

        cookies = cookieDict
        username = value(["username", "uname", "name", "nickname"], fallbackValue: fallback?.username ?? "")
        avatar = value(["avatar", "portrait", "picture"], fallbackValue: fallback?.avatar ?? "")
        vipLevel = value(["vip_level", "vipLevel", "vip"], fallbackValue: fallback?.vipLevel ?? "")

        guard !cookies.isEmpty else { throw BaiduAuthError.invalidResponse }

        // Canonical projections
        merged["cookies"] = cookies
        if !username.isEmpty { merged["username"] = username }
        if !avatar.isEmpty { merged["avatar"] = avatar }
        if !vipLevel.isEmpty { merged["vip_level"] = vipLevel }
        raw = try JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys])
    }

    init(cookieString: String, fallback: BaiduCredential? = nil) throws {
        var cookieDict: [String: String] = [:]
        for pair in cookieString.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                cookieDict[String(parts[0]).trimmingCharacters(in: .whitespaces)] = String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        }
        guard !cookieDict.isEmpty else { throw BaiduAuthError.invalidResponse }
        let payload: [String: Any] = ["cookies": cookieDict]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try self.init(responseData: data, fallback: fallback)
    }

    func mergingProfile(_ responseData: Data) throws -> BaiduCredential {
        try BaiduCredential(responseData: responseData, fallback: self)
    }

    private static func dictionary(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BaiduAuthError.invalidResponse
        }
        return value
    }

    private static func firstString(in objects: [[String: Any]], keys: [String]) -> String? {
        for object in objects {
            for key in keys {
                if let value = object[key] as? String, let value = value.nonempty { return value }
            }
        }
        return nil
    }

    private static func deepMerge(_ base: [String: Any], _ update: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in update {
            if let old = result[key] as? [String: Any], let new = value as? [String: Any] {
                result[key] = deepMerge(old, new)
            } else {
                result[key] = value
            }
        }
        return result
    }
}

// MARK: - 百度网盘错误

enum BaiduAuthError: LocalizedError, Equatable {
    case invalidResponse
    case server(String)
    case timeout
    case cancelled
    case notLoggedIn
    case missingCookie

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "百度网盘响应无效"
        case .server(let text): return "百度网盘请求失败：\(text)"
        case .timeout: return "百度网盘请求超时"
        case .cancelled: return "百度网盘请求已取消"
        case .notLoggedIn: return "百度网盘未登录，请先登录"
        case .missingCookie: return "缺少百度网盘 Cookie，请重新登录"
        }
    }
}

// MARK: - HTTP 客户端协议

protocol BaiduHTTPClientProtocol {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct BaiduHTTPClient: BaiduHTTPClientProtocol {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let result: (Data, URLResponse) = try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error { continuation.resume(throwing: error) }
                else if let data, let response { continuation.resume(returning: (data, response)) }
                else { continuation.resume(throwing: URLError(.badServerResponse)) }
            }.resume()
        }
        guard let response = result.1 as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (result.0, response)
    }
}

// MARK: - 百度网盘认证服务

struct BaiduAuthService {
    // 从 Docs/baidu-strings.txt 取证的用户信息端点
    static let userInfoBase = "https://pan.baidu.com"
    private let client: BaiduHTTPClientProtocol

    init(client: BaiduHTTPClientProtocol = BaiduHTTPClient()) {
        self.client = client
    }

    /// 获取用户信息（使用 Cookie 认证）
    /// 端点：/api/getuserinfo（从 baidu-strings.txt 取证）
    func profile(for credential: BaiduCredential) async throws -> BaiduCredential {
        var request = URLRequest(url: URL(string: "\(Self.userInfoBase)/api/getuserinfo")!)
        request.httpMethod = "GET"
        let cookieHeader = credential.cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        let (data, response) = try await client.data(for: request)
        guard response.statusCode == 200 else {
            throw BaiduAuthError.server("HTTP \(response.statusCode)")
        }
        return try credential.mergingProfile(data)
    }
}
