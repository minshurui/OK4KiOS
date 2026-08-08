import Foundation

struct GuangyaDeviceAuthorization: Equatable, Sendable {
    let deviceCode: String
    let verificationURL: URL
    let expiresIn: TimeInterval
    let interval: TimeInterval
}

struct GuangyaCredential: Equatable, Sendable {
    let raw: Data
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let subject: String
    let name: String
    let picture: String
    let phone: String
    let kaiserFolder: String

    var authorizationHeader: String { "\(tokenType.nonempty ?? "Bearer") \(accessToken)" }
    var displayName: String? { name.nonempty ?? phone.nonempty ?? subject.nonempty }

    init(responseData: Data, fallback: GuangyaCredential? = nil) throws {
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
        subject = value(["sub"], fallbackValue: fallback?.subject ?? "")
        name = value(["name", "nickname"], fallbackValue: fallback?.name ?? "")
        picture = value(["picture", "avatar"], fallbackValue: fallback?.picture ?? "")
        phone = value(["phone_number", "phone"], fallbackValue: fallback?.phone ?? "")
        kaiserFolder = value(["kaiser_folder"], fallbackValue: fallback?.kaiserFolder ?? "")
        guard !accessToken.isEmpty else { throw GuangyaAuthError.invalidResponse }

        // Canonical projections make business readers independent of response aliases,
        // while deepMerge retains every unknown root and nested field.
        merged["access_token"] = accessToken
        if !refreshToken.isEmpty { merged["refresh_token"] = refreshToken }
        merged["token_type"] = tokenType
        if !subject.isEmpty { merged["sub"] = subject }
        if !name.isEmpty { merged["name"] = name }
        if !picture.isEmpty { merged["picture"] = picture }
        if !phone.isEmpty { merged["phone"] = phone }
        if !kaiserFolder.isEmpty { merged["kaiser_folder"] = kaiserFolder }
        raw = try JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys])
    }

    func mergingProfile(_ responseData: Data) throws -> GuangyaCredential {
        try GuangyaCredential(responseData: responseData, fallback: self)
    }

    private static func dictionary(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GuangyaAuthError.invalidResponse
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

enum GuangyaPollResult: Equatable, Sendable {
    case pending
    case authorized(GuangyaCredential)
}

enum GuangyaAuthError: LocalizedError, Equatable {
    case invalidResponse
    case server(String)
    case timeout
    case cancelled
    case missingRefreshToken
    case notLoggedIn

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "光鸭授权响应无效"
        case .server(let text): return "光鸭授权失败：\(text)"
        case .timeout: return "光鸭扫码已超时"
        case .cancelled: return "光鸭扫码已取消"
        case .missingRefreshToken: return "缺少 refresh token，请重新扫码登录"
        case .notLoggedIn: return "光鸭网盘未登录，请先扫码登录"
        }
    }
}

protocol GuangyaHTTPClientProtocol {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct GuangyaHTTPClient: GuangyaHTTPClientProtocol {
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

struct GuangyaAuthService {
    static let clientID = "aMe-8VSlkrbQXpUR"
    static let accountBase = "https://account.guangyapan.com"
    private let client: GuangyaHTTPClientProtocol

    init(client: GuangyaHTTPClientProtocol = GuangyaHTTPClient()) { self.client = client }

    func begin() async throws -> GuangyaDeviceAuthorization {
        let result = try await request(path: "/v1/auth/device/code", method: "POST", body: ["scope": "user", "client_id": Self.clientID])
        let root = try dictionary(result.data)
        let data = (root["data"] as? [String: Any]) ?? root
        guard let code = firstString(data, root, keys: ["device_code", "deviceCode"]),
              let urlText = firstString(data, root, keys: ["verification_uri_complete", "verification_url", "verification_uri", "verificationUriComplete", "verificationUrl", "verificationUri"]),
              let url = URL(string: urlText) else { throw GuangyaAuthError.invalidResponse }
        return .init(deviceCode: code, verificationURL: url,
                     expiresIn: number(data["expires_in"] ?? data["expiresIn"]) ?? 180,
                     interval: max(1, number(data["interval"]) ?? 3))
    }

    func poll(deviceCode: String) async throws -> GuangyaPollResult {
        let result = try await request(path: "/v1/auth/token", method: "POST", body: [
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            "device_code": deviceCode,
            "client_id": Self.clientID
        ], acceptErrorStatus: true)
        let root = try dictionary(result.data)
        if let error = (root["error"] as? String)?.nonempty {
            if ["authorization_pending", "slow_down", "pending"].contains(error) { return .pending }
            throw GuangyaAuthError.server((root["error_description"] as? String)?.nonempty ?? error)
        }
        do { return .authorized(try GuangyaCredential(responseData: result.data)) }
        catch GuangyaAuthError.invalidResponse { return .pending }
    }

    func refresh(_ credential: GuangyaCredential) async throws -> GuangyaCredential {
        guard !credential.refreshToken.isEmpty else { throw GuangyaAuthError.missingRefreshToken }
        let result = try await request(path: "/v1/auth/token", method: "POST", body: [
            "grant_type": "refresh_token", "refresh_token": credential.refreshToken, "client_id": Self.clientID
        ])
        let root = try dictionary(result.data)
        if let error = (root["error"] as? String)?.nonempty {
            throw GuangyaAuthError.server((root["error_description"] as? String)?.nonempty ?? error)
        }
        return try GuangyaCredential(responseData: result.data, fallback: credential)
    }

    func profile(for credential: GuangyaCredential) async throws -> GuangyaCredential {
        let result = try await request(path: "/v1/user/me", method: "GET", authorization: credential.authorizationHeader)
        return try credential.mergingProfile(result.data)
    }

    private func request(path: String, method: String, body: [String: Any]? = nil,
                         authorization: String? = nil, acceptErrorStatus: Bool = false) async throws -> (data: Data, response: HTTPURLResponse) {
        guard let endpoint = URL(string: Self.accountBase + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.timeoutInterval = 20
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        applyHeaders(to: &request, authorization: authorization)
        let result = try await client.data(for: request)
        if !acceptErrorStatus && !(200...299).contains(result.1.statusCode) {
            let root = try? dictionary(result.0)
            let message = (root?["error_description"] as? String)?.nonempty ?? (root?["error"] as? String)?.nonempty
            if let message { throw GuangyaAuthError.server(message) }
            throw HTTPError.status(result.1.statusCode)
        }
        return result
    }

    private func applyHeaders(to request: inout URLRequest, authorization: String?) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://www.guangyapan.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.guangyapan.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
    }

    private func dictionary(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw GuangyaAuthError.invalidResponse }
        return object
    }

    private func firstString(_ primary: [String: Any], _ fallback: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = (primary[key] as? String)?.nonempty { return value }
            if let value = (fallback[key] as? String)?.nonempty { return value }
        }
        return nil
    }

    private func number(_ value: Any?) -> TimeInterval? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return TimeInterval(value) }
        return nil
    }
}

extension String {
    var nonempty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
