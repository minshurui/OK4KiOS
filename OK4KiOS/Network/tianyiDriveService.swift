import Foundation

// MARK: - 天翼云盘网络层
// 端点取证来源：Docs/NetdiskEndpointsEvidence.md 天翼云盘小节 + Docs/tianyi-strings.txt / Docs/tianyi-calls.txt
// 基址 https://api.cloud.189.cn

/// 天翼云盘登录方式（Android L1.l1() 取证）
enum TianyiLoginMethod: String, Sendable {
    case scan = "F2(27)"        // 扫码
    case password = "K2(7)"     // 账号密码
    case sms = "K2(16)"         // 短信验证码
}

/// 天翼云盘凭据（动态 JSON 无损保留未知字段）
struct TianyiCredential: Equatable, Sendable {
    let raw: Data
    let sessionKey: String
    let sessionSecret: String
    let familyId: String?
    let userId: String?
    let userName: String?
    let userNickName: String?
    let memberId: String?
    let memberName: String?
    let accessToken: String?
    let refreshToken: String?

    var displayName: String? {
        userNickName?.nonempty ?? userName?.nonempty ?? memberName?.nonempty
    }

    init(responseData: Data, fallback: TianyiCredential? = nil) throws {
        let response = try Self.dictionary(responseData)
        let previous = try fallback.map { try Self.dictionary($0.raw) } ?? [:]
        var merged = Self.deepMerge(previous, response)

        func value(_ keys: [String], fallbackValue: String? = nil) -> String? {
            Self.firstString(in: [response, previous], keys: keys) ?? fallbackValue
        }

        sessionKey = value(["session_key", "sessionKey"], fallbackValue: fallback?.sessionKey) ?? ""
        sessionSecret = value(["session_secret", "sessionSecret"], fallbackValue: fallback?.sessionSecret) ?? ""
        familyId = value(["familyId", "family_id"])
        userId = value(["userId", "user_id"])
        userName = value(["userName", "user_name"])
        userNickName = value(["userNickName", "user_nick_name", "nickName"])
        memberId = value(["memberId", "member_id"])
        memberName = value(["memberName", "member_name"])
        accessToken = value(["accessToken", "access_token"])
        refreshToken = value(["refreshToken", "refresh_token"])

        guard !sessionKey.isEmpty else { throw TianyiAuthError.invalidResponse }

        // 已知字段投影（业务读取不依赖响应别名）
        merged["session_key"] = sessionKey
        if !sessionSecret.isEmpty { merged["session_secret"] = sessionSecret }
        if let familyId { merged["familyId"] = familyId }
        if let userId { merged["userId"] = userId }
        if let userName { merged["userName"] = userName }
        if let userNickName { merged["userNickName"] = userNickName }
        if let memberId { merged["memberId"] = memberId }
        if let memberName { merged["memberName"] = memberName }
        if let accessToken { merged["accessToken"] = accessToken }
        if let refreshToken { merged["refreshToken"] = refreshToken }

        raw = try JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys])
    }

    func mergingProfile(_ responseData: Data) throws -> TianyiCredential {
        try TianyiCredential(responseData: responseData, fallback: self)
    }

    private static func dictionary(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TianyiAuthError.invalidResponse
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

/// 天翼云盘轮询结果
enum TianyiPollResult: Equatable, Sendable {
    case pending
    case authorized(TianyiCredential)
}

/// 天翼云盘错误
enum TianyiAuthError: LocalizedError, Equatable {
    case invalidResponse
    case server(String)
    case timeout
    case cancelled
    case notLoggedIn
    case protocolPending(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "天翼云盘响应无效"
        case .server(let text): return "天翼云盘请求失败：\(text)"
        case .timeout: return "天翼云盘扫码已超时"
        case .cancelled: return "天翼云盘扫码已取消"
        case .notLoggedIn: return "天翼云盘未登录，请先扫码登录"
        case .protocolPending(let reason): return reason
        }
    }
}

/// 天翼云盘 HTTP 客户端协议（可注入 mock）
protocol TianyiHTTPClientProtocol {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// 默认 URLSession 客户端
struct TianyiHTTPClient: TianyiHTTPClientProtocol {
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

/// 天翼云盘网络服务
struct TianyiAuthService {
    static let baseURL = URL(string: "https://api.cloud.189.cn")!
    private let client: TianyiHTTPClientProtocol

    init(client: TianyiHTTPClientProtocol = TianyiHTTPClient()) {
        self.client = client
    }

    /// 获取用户简要信息（已取证端点）
    func getUserBriefInfo(credential: TianyiCredential) async throws -> TianyiCredential {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("/api/portal/v2/getUserBriefInfo.action"))
        request.httpMethod = "GET"
        request.setValue(credential.sessionKey, forHTTPHeaderField: "sessionKey")
        request.setValue(credential.sessionSecret, forHTTPHeaderField: "sessionSecret")
        let result = try await client.data(for: request)
        guard result.1.statusCode == 200 else {
            throw TianyiAuthError.server("getUserBriefInfo HTTP \(result.1.statusCode)")
        }
        return try credential.mergingProfile(result.0)
    }

    /// 获取用户空间信息（已取证端点）
    func getUserSizeInfo(credential: TianyiCredential) async throws -> TianyiCredential {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("/api/portal/getUserSizeInfo.action"))
        request.httpMethod = "GET"
        request.setValue(credential.sessionKey, forHTTPHeaderField: "sessionKey")
        request.setValue(credential.sessionSecret, forHTTPHeaderField: "sessionSecret")
        let result = try await client.data(for: request)
        guard result.1.statusCode == 200 else {
            throw TianyiAuthError.server("getUserSizeInfo HTTP \(result.1.statusCode)")
        }
        return try credential.mergingProfile(result.0)
    }

    /// 获取家庭列表（已取证端点）
    func getFamilyList(credential: TianyiCredential) async throws -> TianyiCredential {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent("/family/manage/getFamilyList.action"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "clientType", value: "TELEPC"),
            URLQueryItem(name: "version", value: "6.2"),
            URLQueryItem(name: "channelId", value: "web_cloud.189.cn")
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue(credential.sessionKey, forHTTPHeaderField: "sessionKey")
        request.setValue(credential.sessionSecret, forHTTPHeaderField: "sessionSecret")
        let result = try await client.data(for: request)
        guard result.1.statusCode == 200 else {
            throw TianyiAuthError.server("getFamilyList HTTP \(result.1.statusCode)")
        }
        return try credential.mergingProfile(result.0)
    }
}
