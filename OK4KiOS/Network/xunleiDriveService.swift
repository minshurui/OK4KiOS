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
            if let dict = value as? [String: Any], let baseDict = result[key] as? [String: Any] {
                result[key] = deepMerge(baseDict, dict)
            } else {
                result[key] = value
            }
        }
        return result
    }
}

// MARK: - 扫码登录响应
struct XunleiDeviceCodeResponse: Equatable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURI: URL
    let verificationURIComplete: URL?
    let interval: TimeInterval
    let expiresIn: TimeInterval
}

// MARK: - 认证服务
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
        guard let http = result.1 as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (result.0, http)
    }
}

struct XunleiAuthService {
    var baseURL = URL(string: "https://xluser-ssl.xunlei.com/v1")!
    var clientID = "d16d8f6b-e0c8-48f0-87c4-4f43a34d37c0"
    var client: XunleiHTTPClientProtocol = XunleiHTTPClient()

    // MARK: 创建扫码登录
    func createQrcodeLogin() async throws -> XunleiDeviceCodeResponse {
        let url = baseURL.appendingPathComponent("auth/device/code")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID(), forHTTPHeaderField: "x-device-id")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": clientID,
            "scope": "user"
        ])

        let (data, response) = try await client.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw XunleiAuthError.invalidResponse
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let deviceCode = json["device_code"] as? String,
              let userCode = json["user_code"] as? String,
              let verificationURIString = json["verification_uri"] as? String,
              let verificationURI = URL(string: verificationURIString) else {
            throw XunleiAuthError.invalidResponse
        }

        let verificationURIComplete = (json["verification_uri_complete"] as? String).flatMap(URL.init)
        let interval = (json["interval"] as? TimeInterval) ?? 3
        let expiresIn = (json["expires_in"] as? TimeInterval) ?? 300

        return XunleiDeviceCodeResponse(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURI: verificationURI,
            verificationURIComplete: verificationURIComplete,
            interval: interval,
            expiresIn: expiresIn
        )
    }

    // MARK: 轮询扫码状态
    func pollQrcodeLogin(deviceCode: String, clientID: String) async throws -> XunleiCredential {
        let url = baseURL.appendingPathComponent("auth/token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID(), forHTTPHeaderField: "x-device-id")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            "client_id": clientID,
            "device_code": deviceCode
        ])

        let (data, response) = try await client.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw XunleiAuthError.invalidResponse
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        // 错误处理
        if let error = json["error"] as? String {
            switch error {
            case "authorization_pending", "slow_down":
                throw XunleiAuthError.pending
            case "access_denied", "expired_token":
                throw XunleiAuthError.expired
            case "invalid_grant":
                if json["access_token"] == nil {
                    throw XunleiAuthError.invalidGrant
                }
            default:
                throw XunleiAuthError.serverError(error)
            }
        }

        // 成功解析
        guard let accessToken = json["access_token"] as? String, !accessToken.isEmpty else {
            throw XunleiAuthError.invalidResponse
        }

        return try XunleiCredential(responseData: data)
    }

    // MARK: 获取用户信息
    func userInfo(credential: XunleiCredential) async throws -> XunleiCredential {
        let url = baseURL.appendingPathComponent("user/me")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(credential.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue(deviceID(), forHTTPHeaderField: "x-device-id")

        let (data, response) = try await client.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw XunleiAuthError.invalidResponse
        }

        return try credential.mergingProfile(data)
    }

    // MARK: 刷新 Token
    func refreshToken(_ refreshToken: String) async throws -> XunleiCredential {
        let url = baseURL.appendingPathComponent("auth/token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID(), forHTTPHeaderField: "x-device-id")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refreshToken
        ])

        let (data, response) = try await client.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw XunleiAuthError.invalidResponse
        }

        return try XunleiCredential(responseData: data)
    }

    // MARK: 设备 ID
    private func deviceID() -> String {
        // 与 Android 相同语义：持久化的随机 id；iOS 侧用固定前缀+时间
        "ok4k-ios-\(Int(Date().timeIntervalSince1970 * 1000) % 100000000)"
    }
}

// MARK: - 错误类型
enum XunleiAuthError: Error, Equatable {
    case notLoggedIn
    case invalidResponse
    case pending
    case expired
    case invalidGrant
    case serverError(String)
}
