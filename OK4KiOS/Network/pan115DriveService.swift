import Foundation

// MARK: - 115网盘 网络层模型

struct Pan115QRCodeResponse: Equatable, Sendable {
    let qrCode: String
    let uid: String
    let time: Int
    let sign: String
    let appID: String
}

struct Pan115TokenResponse: Equatable, Sendable {
    let status: Bool
    let message: String
    let data: Pan115TokenData?
}

struct Pan115TokenData: Equatable, Sendable {
    let token: String
    let userID: String
    let userName: String
    let avatar: String
}

struct Pan115Credential: Equatable, Sendable {
    let raw: Data
    let token: String
    let userID: String
    let userName: String
    let avatar: String

    var displayName: String? { userName.nonempty ?? userID.nonempty }

    init(responseData: Data, fallback: Pan115Credential? = nil) throws {
        let response = try Self.dictionary(responseData)
        let previous = try fallback.map { try Self.dictionary($0.raw) } ?? [:]
        var merged = Self.deepMerge(previous, response)
        let responseDataObject = response["data"] as? [String: Any] ?? response
        let previousDataObject = previous["data"] as? [String: Any] ?? previous

        func value(_ keys: [String], fallbackValue: String = "") -> String {
            Self.firstString(in: [responseDataObject, response, previousDataObject, previous], keys: keys) ?? fallbackValue
        }

        token = value(["token", "access_token", "accessToken"], fallbackValue: fallback?.token ?? "")
        userID = value(["user_id", "userId", "uid"], fallbackValue: fallback?.userID ?? "")
        userName = value(["user_name", "userName", "name", "nickname"], fallbackValue: fallback?.userName ?? "")
        avatar = value(["avatar", "picture"], fallbackValue: fallback?.avatar ?? "")
        guard !token.isEmpty else { throw Pan115AuthError.invalidResponse }

        merged["token"] = token
        if !userID.isEmpty { merged["user_id"] = userID }
        if !userName.isEmpty { merged["user_name"] = userName }
        if !avatar.isEmpty { merged["avatar"] = avatar }
        raw = try JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys])
    }

    func mergingProfile(_ responseData: Data) throws -> Pan115Credential {
        try Pan115Credential(responseData: responseData, fallback: self)
    }

    private static func dictionary(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Pan115AuthError.invalidResponse
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

enum Pan115PollResult: Equatable, Sendable {
    case pending
    case authorized(Pan115Credential)
}

enum Pan115AuthError: LocalizedError, Equatable {
    case invalidResponse
    case server(String)
    case timeout
    case cancelled
    case notLoggedIn

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "115网盘授权响应无效"
        case .server(let text): return "115网盘授权失败：\(text)"
        case .timeout: return "115网盘扫码已超时"
        case .cancelled: return "115网盘扫码已取消"
        case .notLoggedIn: return "115网盘未登录，请先扫码登录"
        }
    }
}

protocol Pan115HTTPClientProtocol {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct Pan115HTTPClient: Pan115HTTPClientProtocol {
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

struct Pan115AuthService {
    static let qrcodeBase = "https://passportapi.115.com/app/1.0/alipaymini/1.0/login/qrcode/"
    static let tokenBase = "https://qrcodeapi.115.com/api/1.0/alipaymini/1.0/token/"
    static let deviceHeader = "adprovider/8.56.0.1134 netWorkType/WIFI appid/40 deviceName/iPhone"
    private let client: Pan115HTTPClientProtocol

    init(client: Pan115HTTPClientProtocol = Pan115HTTPClient()) { self.client = client }

    func begin() async throws -> Pan115QRCodeResponse {
        var request = URLRequest(url: URL(string: Self.qrcodeBase)!)
        request.httpMethod = "GET"
        request.setValue(Self.deviceHeader, forHTTPHeaderField: "User-Agent")
        let result = try await client.data(for: request)
        let root = try dictionary(result.data)
        let data = (root["data"] as? [String: Any]) ?? root
        guard let qrCode = firstString(data, root, keys: ["qrcode", "qr_code", "qrCode"]),
              let uid = firstString(data, root, keys: ["uid", "user_id", "userId"]),
              let time = number(data["time"] ?? data["expires_in"]) ?? 180,
              let sign = firstString(data, root, keys: ["sign"]) else { throw Pan115AuthError.invalidResponse }
        return .init(qrCode: qrCode, uid: uid, time: time, sign: sign, appID: "40")
    }

    func poll(uid: String, time: Int, sign: String) async throws -> Pan115PollResult {
        var components = URLComponents(string: Self.tokenBase)!
        components.queryItems = [
            URLQueryItem(name: "uid", value: uid),
            URLQueryItem(name: "time", value: String(time)),
            URLQueryItem(name: "sign", value: sign)
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue(Self.deviceHeader, forHTTPHeaderField: "User-Agent")
        let result = try await client.data(for: request)
        let root = try dictionary(result.data)
        let status = (root["status"] as? Bool) ?? false
        let message = (root["message"] as? String) ?? ""
        if status {
            let data = (root["data"] as? [String: Any]) ?? [:]
            guard let token = firstString(data, root, keys: ["token", "access_token", "accessToken"]) else {
                throw Pan115AuthError.invalidResponse
            }
            let credential = try Pan115Credential(responseData: result.data)
            return .authorized(credential)
        } else if message.contains("pending") || message.contains("wait") || message.contains("未扫描") {
            return .pending
        } else {
            throw Pan115AuthError.server(message)
        }
    }

    func profile(for credential: Pan115Credential) async throws -> Pan115Credential {
        var request = URLRequest(url: URL(string: "https://my.115.com/?ct=ajax&ac=nav")!)
        request.httpMethod = "GET"
        request.setValue(Self.deviceHeader, forHTTPHeaderField: "User-Agent")
        request.setValue("token=\(credential.token)", forHTTPHeaderField: "Cookie")
        let result = try await client.data(for: request)
        return try credential.mergingProfile(result.data)
    }

    private static func dictionary(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Pan115AuthError.invalidResponse
        }
        return value
    }

    private static func firstString(_ objects: [String: Any]..., keys: [String]) -> String? {
        for object in objects {
            for key in keys {
                if let value = object[key] as? String, let value = value.nonempty { return value }
            }
        }
        return nil
    }

    private static func number(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string) }
        return nil
    }
}
