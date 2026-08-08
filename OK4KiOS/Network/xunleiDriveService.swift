import Foundation

// MARK: - 迅雷网盘网络层
// 端点取证来源：Docs/NetdiskEndpointsEvidence.md 迅雷小节、Docs/xunlei-strings.txt、Docs/xunlei-calls.txt
// API 基址：https://api-pan.xunlei.com/drive/v1/
// 认证基址：https://xluser-ssl.xunlei.com/v1/auth/token

struct XunleiDeviceAuthorization: Equatable, Sendable {
    let deviceCode: String
    let verificationURL: URL
    let expiresIn: TimeInterval
    let interval: TimeInterval
}

struct XunleiCredential: Equatable, Sendable {
    let raw: Data
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let userID: String
    let name: String
    let avatar: String
    let phone: String

    var authorizationHeader: String { "\(tokenType.nonempty ?? "Bearer") \(accessToken)" }
    var displayName: String? { name.nonempty ?? phone.nonempty ?? userID.nonempty }

    init(responseData: Data, fallback: XunleiCredential? = nil) throws {
        let response = try Self.dictionary(responseData)
        let previous = try fallback.map { try Self.dictionary($0.raw) } ?? [:]
        var merged = Self.deepMerge(previous, response)
        let responseDataObject = response["data"] as? [String: Any] ?? response
        let previousDataObject = previous["data"] as? [String: Any] ?? previous

        func value(_ keys: [String], fallbackValue: String = "") -> String {
            Self.firstString(in: [responseDataObject, response, previousDataObject, previous], keys: keys) ?? fallbackValue
        }

        accessToken = value(["access_token", "accessToken"], fallbackValue: fallback?.accessToken ?? "")
        refreshToken = value(["refresh_token", "refreshToken"], fallbackValue: fallback?.refreshToken ?? "")
        tokenType = value(["token_type", "tokenType"], fallbackValue: fallback?.tokenType ?? "Bearer").nonempty ?? "Bearer"
        userID = value(["user_id", "userId", "sub"], fallbackValue: fallback?.userID ?? "")
        name = value(["name", "nickname", "user_name"], fallbackValue: fallback?.name ?? "")
        avatar = value(["avatar", "picture", "avatar_url"], fallbackValue: fallback?.avatar ?? "")
        phone = value(["phone", "phone_number", "mobile"], fallbackValue: fallback?.phone ?? "")
        guard !accessToken.isEmpty else { throw XunleiAuthError.invalidResponse }

        // Canonical projections make business readers independent of response aliases,
        // while deepMerge retains every unknown root and nested field.
        merged["access_token"] = accessToken
        if !refreshToken.isEmpty { merged["refresh_token"] = refreshToken }
        merged["token_type"] = tokenType
        if !userID.isEmpty { merged["user_id"] = userID }
        if !name.isEmpty { merged["name"] = name }
        if !avatar.isEmpty { merged["avatar"] = avatar }
        if !phone.isEmpty { merged["phone"] = phone }
        raw = try JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys])
    }

    func mergingProfile(_ responseData: Data) throws -> XunleiCredential {
        try XunleiCredential(responseData: responseData, fallback: self)
    }

    private static func dictionary(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw XunleiAuthError.invalidResponse
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

enum XunleiPollResult: Equatable, Sendable {
    case pending
    case authorized(XunleiCredential)
}

enum XunleiAuthError: LocalizedError, Equatable {
    case invalidResponse
    case server(String)
    case timeout
    case cancelled
    case missingRefreshToken
    case notLoggedIn

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "迅雷授权响应无效"
        case .server(let text): return "迅雷授权失败：\(text)"
        case .timeout: return "迅雷扫码已超时"
        case .cancelled: return "迅雷扫码已取消"
        case .missingRefreshToken: return "缺少 refresh token，请重新扫码登录"
        case .notLoggedIn: return "迅雷网盘未登录，请先扫码登录"
        }
    }
}

protocol XunleiHTTPClientProtocol {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct XunleiHTTPClient: XunleiHTTPClientProtocol {
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

struct XunleiAuthService {
    static let authBase = "https://xluser-ssl.xunlei.com/v1/auth/token"
    static let apiBase = "https://api-pan.xunlei.com/drive/v1/"
    // Android L1.p1() 取证：扫码 K2(10) / Token JSON K2(11)
    // 桌面 UA 已取证：Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) uc-cloud-drive/2...
    static let desktopUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) uc-cloud-drive/2.0.0"
    private let client: XunleiHTTPClientProtocol

    init(client: XunleiHTTPClientProtocol = XunleiHTTPClient()) { self.client = client }

    func begin() async throws -> XunleiDeviceAuthorization {
        // Android L1.p1() 扫码创建：K2(10) 表示扫码登录方式
        // 端点：POST https://xluser-ssl.xunlei.com/v1/auth/token
        // 请求体字段未完整取证，诚实抛 protocolPending
        throw FishDriveError.protocolPending("迅雷扫码创建请求体字段未完整取证（Android L1.p1() K2(10)），无法构造请求")
    }

    func poll(deviceCode: String) async throws -> XunleiPollResult {
        // Android L1.p1() 轮询：K2(10) 扫码登录轮询
        // 轮询端点与成功判定字段未完整取证，诚实抛 protocolPending
        throw FishDriveError.protocolPending("迅雷扫码轮询端点与成功判定字段未完整取证（Android L1.p1() K2(10)），无法构造请求")
    }

    func refresh(_ credential: XunleiCredential) async throws -> XunleiCredential {
        guard !credential.refreshToken.isEmpty else { throw XunleiAuthError.missingRefreshToken }
        // 端点：POST https://xluser-ssl.xunlei.com/v1/auth/token
        // 请求体字段未完整取证，诚实抛 protocolPending
        throw FishDriveError.protocolPending("迅雷 refresh_token 请求体字段未完整取证，无法构造请求")
    }

    func profile(for credential: XunleiCredential) async throws -> XunleiCredential {
        // 端点：GET https://api-pan.xunlei.com/drive/v1/user/me
        // 响应字段未完整取证，诚实抛 protocolPending
        throw FishDriveError.protocolPending("迅雷 /user/me 响应字段未完整取证，无法解析用户资料")
    }

    private func request(path: String, method: String, body: [String: Any]? = nil, token: String? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: path)!)
        request.httpMethod = method
        request.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return try await client.data(for: request)
    }
}
