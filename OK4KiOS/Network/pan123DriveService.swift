import Foundation

// MARK: - 模型

struct Pan123DeviceAuthorization: Equatable, Sendable {
    let deviceCode: String
    let verificationURL: URL
    let expiresIn: TimeInterval
    let interval: TimeInterval
}

struct Pan123Credential: Equatable, Sendable {
    let raw: Data
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let openID: String
    let name: String
    let avatar: String
    let phone: String

    var authorizationHeader: String { "\(tokenType.nonempty ?? "Bearer") \(accessToken)" }
    var displayName: String? { name.nonempty ?? phone.nonempty ?? openID.nonempty }

    init(responseData: Data, fallback: Pan123Credential? = nil) throws {
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
        openID = value(["open_id", "openId", "sub"], fallbackValue: fallback?.openID ?? "")
        name = value(["name", "nickname"], fallbackValue: fallback?.name ?? "")
        avatar = value(["avatar", "picture"], fallbackValue: fallback?.avatar ?? "")
        phone = value(["phone_number", "phone"], fallbackValue: fallback?.phone ?? "")
        guard !accessToken.isEmpty else { throw Pan123AuthError.invalidResponse }

        // Canonical projections make business readers independent of response aliases,
        // while deepMerge retains every unknown root and nested field.
        merged["access_token"] = accessToken
        if !refreshToken.isEmpty { merged["refresh_token"] = refreshToken }
        merged["token_type"] = tokenType
        if !openID.isEmpty { merged["open_id"] = openID }
        if !name.isEmpty { merged["name"] = name }
        if !avatar.isEmpty { merged["avatar"] = avatar }
        if !phone.isEmpty { merged["phone"] = phone }
        raw = try JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys])
    }

    func mergingProfile(_ responseData: Data) throws -> Pan123Credential {
        try Pan123Credential(responseData: responseData, fallback: self)
    }

    private static func dictionary(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Pan123AuthError.invalidResponse
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

enum Pan123PollResult: Equatable, Sendable {
    case pending
    case authorized(Pan123Credential)
}

enum Pan123AuthError: LocalizedError, Equatable {
    case invalidResponse
    case server(String)
    case timeout
    case cancelled
    case missingRefreshToken
    case notLoggedIn

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "123网盘授权响应无效"
        case .server(let text): return "123网盘授权失败：\(text)"
        case .timeout: return "123网盘扫码已超时"
        case .cancelled: return "123网盘扫码已取消"
        case .missingRefreshToken: return "缺少 refresh token，请重新扫码登录"
        case .notLoggedIn: return "123网盘未登录，请先扫码登录"
        }
    }
}

protocol Pan123HTTPClientProtocol {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct Pan123HTTPClient: Pan123HTTPClientProtocol {
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

struct Pan123AuthService {
    static let clientID = "OK4KiOS"
    static let oauthBase = "https://open-api.123pan.com"
    static let litepanBase = "https://oauth.litepan.top"
    private let client: Pan123HTTPClientProtocol

    init(client: Pan123HTTPClientProtocol = Pan123HTTPClient()) { self.client = client }

    func begin() async throws -> Pan123DeviceAuthorization {
        // 123网盘 OAuth 授权端点：创建二维码会话
        let result = try await request(path: "/api/v1/oauth2/user/authorize", method: "POST", base: Self.oauthBase, body: ["client_id": Self.clientID, "response_type": "code", "scope": "user:read,file:read"])
        let root = try dictionary(result.data)
        let data = (root["data"] as? [String: Any]) ?? root
        guard let code = firstString(data, root, keys: ["device_code", "deviceCode", "code"]),
              let urlText = firstString(data, root, keys: ["verification_uri_complete", "verification_url", "verification_uri", "verificationUriComplete", "verificationUrl", "verificationUri", "qr_url", "qrUrl"]),
              let url = URL(string: urlText) else { throw Pan123AuthError.invalidResponse }
        return .init(deviceCode: code, verificationURL: url,
                     expiresIn: number(data["expires_in"] ?? data["expiresIn"]) ?? 180,
                     interval: max(1, number(data["interval"]) ?? 3))
    }

    func poll(deviceCode: String) async throws -> Pan123PollResult {
        // litepan 中转轮询端点
        let result = try await request(path: "/api/oauth/status/\(deviceCode)", method: "GET", base: Self.litepanBase, body: nil)
        let root = try dictionary(result.data)
        let data = (root["data"] as? [String: Any]) ?? root
        let status = firstString(data, root, keys: ["status", "state"]) ?? ""
        switch status {
        case "pending", "waiting", "scanning":
            return .pending
        case "authorized", "success", "confirmed":
            // 授权成功后，从响应中提取 token 信息
            let credential = try Pan123Credential(responseData: result.data)
            return .authorized(credential)
        case "expired", "timeout":
            throw Pan123AuthError.timeout
        case "cancelled", "canceled":
            throw Pan123AuthError.cancelled
        default:
            // 未知状态：尝试从响应中提取 token，若成功则视为已授权
            if let credential = try? Pan123Credential(responseData: result.data) {
                return .authorized(credential)
            }
            return .pending
        }
    }

    func refresh(_ credential: Pan123Credential) async throws -> Pan123Credential {
        guard !credential.refreshToken.isEmpty else { throw Pan123AuthError.missingRefreshToken }
        // litepan 中转刷新端点
        let result = try await request(path: "/api/oauth/refresh", method: "POST", base: Self.litepanBase, body: ["refresh_token": credential.refreshToken])
        return try Pan123Credential(responseData: result.data, fallback: credential)
    }

    func profile(for credential: Pan123Credential) async throws -> Pan123Credential {
        // 用户信息端点
        var request = URLRequest(url: URL(string: "\(Self.oauthBase)/api/user/info")!)
        request.httpMethod = "GET"
        request.setValue(credential.authorizationHeader, forHTTPHeaderField: "Authorization")
        let result = try await client.data(for: request)
        guard result.1.statusCode == 200 else {
            throw Pan123AuthError.server("HTTP \(result.1.statusCode)")
        }
        return try credential.mergingProfile(result.0)
    }

    // MARK: - 内部工具

    private func request(path: String, method: String, base: String, body: [String: Any]?) async throws -> (data: Data, response: HTTPURLResponse) {
        var request = URLRequest(url: URL(string: base + path)!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let result = try await client.data(for: request)
        guard result.1.statusCode == 200 else {
            throw Pan123AuthError.server("HTTP \(result.1.statusCode)")
        }
        return result
    }

    private func dictionary(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Pan123AuthError.invalidResponse
        }
        return value
    }

    private func firstString(_ objects: [String: Any]..., keys: [String]) -> String? {
        for object in objects {
            for key in keys {
                if let value = object[key] as? String, !value.isEmpty { return value }
            }
        }
        return nil
    }

    private func number(_ value: Any?) -> TimeInterval? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return TimeInterval(string) }
        return nil
    }
}
