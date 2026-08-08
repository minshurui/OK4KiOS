import Foundation

// MARK: - 阿里云盘授权响应

struct AliDeviceAuthorization: Equatable, Sendable {
    let qrCodeUrl: String
    let sid: String
    let expiresIn: TimeInterval
    let interval: TimeInterval
}

// MARK: - 阿里云盘凭据

struct AliCredential: Equatable, Sendable {
    let raw: Data
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let displayName: String?
    let userId: String?

    var authorizationHeader: String { "\(tokenType.nonempty ?? "Bearer") \(accessToken)" }

    init(responseData: Data, fallback: AliCredential? = nil) throws {
        let response = try Self.dictionary(responseData)
        let previous = try fallback.map { try Self.dictionary($0.raw) } ?? [:]
        var merged = Self.deepMerge(previous, response)

        func value(_ keys: [String], fallbackValue: String = "") -> String {
            Self.firstString(in: [response, previous], keys: keys) ?? fallbackValue
        }

        accessToken = value(["access_token", "accessToken"], fallbackValue: fallback?.accessToken ?? "")
        refreshToken = value(["refresh_token", "refreshToken"], fallbackValue: fallback?.refreshToken ?? "")
        tokenType = value(["token_type", "tokenType"], fallbackValue: fallback?.tokenType ?? "Bearer").nonempty ?? "Bearer"
        displayName = value(["name", "nickname", "display_name", "displayName"]).nonempty ?? fallback?.displayName
        userId = value(["user_id", "userId", "sub"]).nonempty ?? fallback?.userId
        guard !accessToken.isEmpty else { throw AliAuthError.invalidResponse }

        // Canonical projections make business readers independent of response aliases,
        // while deepMerge retains every unknown root and nested field.
        merged["access_token"] = accessToken
        if !refreshToken.isEmpty { merged["refresh_token"] = refreshToken }
        merged["token_type"] = tokenType
        if let displayName { merged["display_name"] = displayName }
        if let userId { merged["user_id"] = userId }
        raw = try JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys])
    }

    func mergingProfile(_ responseData: Data) throws -> AliCredential {
        try AliCredential(responseData: responseData, fallback: self)
    }

    private static func dictionary(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AliAuthError.invalidResponse
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

// MARK: - 轮询结果

enum AliPollResult: Equatable, Sendable {
    case pending
    case authorized(AliCredential)
}

// MARK: - 错误

enum AliAuthError: LocalizedError, Equatable {
    case invalidResponse
    case server(String)
    case timeout
    case cancelled
    case missingRefreshToken
    case notLoggedIn
    case protocolPending(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "阿里云盘授权响应无效"
        case .server(let text): return "阿里云盘授权失败：\(text)"
        case .timeout: return "阿里云盘扫码已超时"
        case .cancelled: return "阿里云盘扫码已取消"
        case .missingRefreshToken: return "缺少 refresh token，请重新扫码登录"
        case .notLoggedIn: return "阿里云盘未登录，请先扫码登录"
        case .protocolPending(let reason): return reason
        }
    }
}

// MARK: - HTTP 客户端协议

protocol AliHTTPClientProtocol {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct AliHTTPClient: AliHTTPClientProtocol {
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

// MARK: - 阿里云盘网络服务

struct AliAuthService {
    static let clientID = "10e184c407cb4d8087f9d3b8f1fd2c23"
    static let apiBase = "https://api.aliyundrive.com"
    static let oauthBase = "https://open.aliyundrive.com"
    static let tokenBase = "https://auth.aliyundrive.com"
    static let refreshBase = "https://auth.xiaoya.pro"

    private let client: AliHTTPClientProtocol

    init(client: AliHTTPClientProtocol = AliHTTPClient()) { self.client = client }

    /// 创建扫码授权会话（Android L1.G0() 对应 OAuth authorize 端点）
    func begin() async throws -> AliDeviceAuthorization {
        let url = URL(string: "\(Self.oauthBase)/oauth/users/authorize")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": Self.clientID,
            "redirect_uri": "https://opentoken.xiaoya.pro/callback",
            "scope": "user:base,file:all:read,file:all:write",
            "state": ""
        ])

        let (data, response) = try await client.data(for: request)
        guard response.statusCode == 200 else {
            throw AliAuthError.server("HTTP \(response.statusCode)")
        }
        let root = try dictionary(data)
        guard let qrCodeUrl = firstString(root, keys: ["qrCodeUrl", "qr_code_url", "verification_uri_complete", "verificationUrl"]),
              let sid = firstString(root, keys: ["sid", "deviceCode", "device_code"]),
              let qrURL = URL(string: qrCodeUrl) else {
            throw AliAuthError.invalidResponse
        }
        return AliDeviceAuthorization(
            qrCodeUrl: qrURL.absoluteString,
            sid: sid,
            expiresIn: number(root["expiresIn"] ?? root["expires_in"]) ?? 300,
            interval: max(1, number(root["interval"]) ?? 3)
        )
    }

    /// 轮询授权结果（Android 轮询间隔 3s，超时 300s）
    func poll(sid: String) async throws -> AliPollResult {
        let url = URL(string: "\(Self.oauthBase)/oauth/users/authorize/status")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["sid": sid])

        let (data, response) = try await client.data(for: request)
        if response.statusCode == 400 {
            let root = try dictionary(data)
            if let error = firstString(root, keys: ["error", "error_code"]), error.contains("pending") {
                return .pending
            }
            throw AliAuthError.server(error ?? "HTTP 400")
        }
        guard response.statusCode == 200 else {
            throw AliAuthError.server("HTTP \(response.statusCode)")
        }
        let root = try dictionary(data)
        if let authCode = firstString(root, keys: ["authCode", "auth_code", "code"]) {
            let token = try await exchangeCode(authCode)
            return .authorized(token)
        }
        if let error = firstString(root, keys: ["error", "error_code"]) {
            if error.contains("pending") { return .pending }
            throw AliAuthError.server(error)
        }
        throw AliAuthError.invalidResponse
    }

    /// 用授权码换取 token（Android 对应 auth.aliyundrive.com/v2/account/token）
    private func exchangeCode(_ code: String) async throws -> AliCredential {
        let url = URL(string: "\(Self.tokenBase)/v2/account/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": Self.clientID
        ])

        let (data, response) = try await client.data(for: request)
        guard response.statusCode == 200 else {
            throw AliAuthError.server("HTTP \(response.statusCode)")
        }
        return try AliCredential(responseData: data)
    }

    /// 刷新 token（Android 对应 auth.xiaoya.pro/api/ali_open/refresh）
    func refresh(_ credential: AliCredential) async throws -> AliCredential {
        guard !credential.refreshToken.isEmpty else { throw AliAuthError.missingRefreshToken }
        let url = URL(string: "\(Self.refreshBase)/api/ali_open/refresh")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": credential.refreshToken])

        let (data, response) = try await client.data(for: request)
        guard response.statusCode == 200 else {
            throw AliAuthError.server("HTTP \(response.statusCode)")
        }
        return try AliCredential(responseData: data, fallback: credential)
    }

    /// 获取用户信息（Android 对应 /v2/databox/get_personal_info）
    func profile(for credential: AliCredential) async throws -> AliCredential {
        let url = URL(string: "\(Self.apiBase)/v2/databox/get_personal_info")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(credential.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [:], options: [])

        let (data, response) = try await client.data(for: request)
        guard response.statusCode == 200 else {
            throw AliAuthError.server("HTTP \(response.statusCode)")
        }
        return try credential.mergingProfile(data)
    }

    // MARK: - 工具方法

    private func dictionary(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AliAuthError.invalidResponse
        }
        return value
    }

    private func firstString(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, let value = value.nonempty { return value }
        }
        return nil
    }

    private func number(_ value: Any?) -> TimeInterval? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return TimeInterval(string) }
        return nil
    }
}
