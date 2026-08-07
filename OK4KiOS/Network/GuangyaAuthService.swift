import Foundation

struct GuangyaDeviceAuthorization: Equatable, Sendable {
    let deviceCode: String
    let verificationURL: URL
    let expiresIn: TimeInterval
    let interval: TimeInterval
}

struct GuangyaCredential: Codable, Equatable, Sendable {
    let raw: Data
    let accessToken: String
    let refreshToken: String
    let tokenType: String

    init(responseData: Data) throws {
        let object = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        let data = (object?["data"] as? [String: Any]) ?? object ?? [:]
        func string(_ snake: String, _ camel: String) -> String {
            (data[snake] as? String) ?? (data[camel] as? String) ?? (object?[snake] as? String) ?? (object?[camel] as? String) ?? ""
        }
        accessToken = string("access_token", "accessToken")
        refreshToken = string("refresh_token", "refreshToken")
        tokenType = string("token_type", "tokenType")
        guard !accessToken.isEmpty else { throw GuangyaAuthError.invalidResponse }
        raw = responseData
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

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "光鸭授权响应无效"
        case .server(let text): return "光鸭授权失败：\(text)"
        case .timeout: return "光鸭扫码已超时"
        case .cancelled: return "光鸭扫码已取消"
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
    private let client: GuangyaHTTPClientProtocol

    init(client: GuangyaHTTPClientProtocol = GuangyaHTTPClient()) { self.client = client }

    func begin() async throws -> GuangyaDeviceAuthorization {
        let body: [String: Any] = ["scope": "user", "client_id": Self.clientID]
        let result = try await post(url: "https://account.guangyapan.com/v1/auth/device/code", body: body, acceptErrorStatus: false)
        let root = try dictionary(result.data)
        let data = (root["data"] as? [String: Any]) ?? root
        guard let code = firstString(data, root, keys: ["device_code", "deviceCode"]),
              let urlText = firstString(data, root, keys: ["verification_uri_complete", "verification_url", "verification_uri", "verificationUriComplete", "verificationUrl", "verificationUri"]),
              let url = URL(string: urlText) else { throw GuangyaAuthError.invalidResponse }
        return .init(
            deviceCode: code,
            verificationURL: url,
            expiresIn: number(data["expires_in"] ?? data["expiresIn"]) ?? 180,
            interval: max(1, number(data["interval"]) ?? 3)
        )
    }

    func poll(deviceCode: String) async throws -> GuangyaPollResult {
        let body: [String: Any] = [
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            "device_code": deviceCode,
            "client_id": Self.clientID
        ]
        let result = try await post(url: "https://account.guangyapan.com/v1/auth/token", body: body, acceptErrorStatus: true)
        let root = try dictionary(result.data)
        if let error = root["error"] as? String, !error.isEmpty {
            if ["authorization_pending", "slow_down", "pending"].contains(error) { return .pending }
            let description = (root["error_description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            throw GuangyaAuthError.server(description ?? error)
        }
        if let code = root["code"] as? Int, code != 0, code != 200 { return .pending }
        do { return .authorized(try GuangyaCredential(responseData: result.data)) }
        catch GuangyaAuthError.invalidResponse { return .pending }
    }

    private func post(url: String, body: [String: Any], acceptErrorStatus: Bool) async throws -> (data: Data, response: HTTPURLResponse) {
        guard let endpoint = URL(string: url) else { throw URLError(.badURL) }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://www.guangyapan.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.guangyapan.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", forHTTPHeaderField: "User-Agent")
        let result = try await client.data(for: request)
        if !acceptErrorStatus && !(200...299).contains(result.1.statusCode) {
            throw HTTPError.status(result.1.statusCode)
        }
        return result
    }

    private func dictionary(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw GuangyaAuthError.invalidResponse }
        return object
    }

    private func firstString(_ primary: [String: Any], _ fallback: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = primary[key] as? String, !value.isEmpty { return value }
            if let value = fallback[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    private func number(_ value: Any?) -> TimeInterval? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return TimeInterval(value) }
        return nil
    }
}
