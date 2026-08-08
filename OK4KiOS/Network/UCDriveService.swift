import Foundation

struct UCDeviceCodeResponse: Equatable, Sendable {
    let deviceCode: String
    let qrContent: String
    let expiresIn: TimeInterval
    let interval: TimeInterval
    let openURL: URL?
}

struct UCCredential: Equatable, Sendable {
    let raw: Data
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let uid: String
    let displayName: String
    let avatar: String
    let isVip: Bool

    var authorizationHeader: String { "\(tokenType.nonempty ?? "Bearer") \(accessToken)" }

    init(responseData: Data, fallback: UCCredential? = nil) throws {
        let response = try Self.dictionary(responseData)
        let previous = try fallback.map { try Self.dictionary($0.raw) } ?? [:]
        var merged = Self.deepMerge(previous, response)
        let data = response["data"] as? [String: Any] ?? response
        let prevData = previous["data"] as? [String: Any] ?? previous

        func value(_ keys: [String], fallbackValue: String = "") -> String {
            Self.firstString(in: [data, response, prevData, previous], keys: keys) ?? fallbackValue
        }

        accessToken = value(["access_token", "accessToken", "token"], fallbackValue: fallback?.accessToken ?? "")
        refreshToken = value(["refresh_token", "refreshToken"], fallbackValue: fallback?.refreshToken ?? "")
        tokenType = value(["token_type", "tokenType"], fallbackValue: fallback?.tokenType ?? "Bearer").nonempty ?? "Bearer"
        uid = value(["uid", "user_id", "userId", "sub"], fallbackValue: fallback?.uid ?? "")
        displayName = value(["display_name", "displayName", "nickname", "name"], fallbackValue: fallback?.displayName ?? "")
        avatar = value(["avatar", "picture", "head_url"], fallbackValue: fallback?.avatar ?? "")
        isVip = (data["is_vip"] as? Bool) ?? (data["vip"] as? Bool) ?? (fallback?.isVip ?? false)
        guard !accessToken.isEmpty else { throw UCAuthError.invalidResponse }

        merged["access_token"] = accessToken
        if !refreshToken.isEmpty { merged["refresh_token"] = refreshToken }
        merged["token_type"] = tokenType
        if !uid.isEmpty { merged["uid"] = uid }
        if !displayName.isEmpty { merged["display_name"] = displayName }
        if !avatar.isEmpty { merged["avatar"] = avatar }
        merged["is_vip"] = isVip
        raw = try JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys])
    }

    func mergingProfile(_ responseData: Data) throws -> UCCredential {
        try UCCredential(responseData: responseData, fallback: self)
    }

    private static func dictionary(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UCAuthError.invalidResponse
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

enum UCAuthError: LocalizedError, Equatable {
    case invalidResponse
    case notLoggedIn
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "UC 网盘授权响应无效"
        case .notLoggedIn: return "UC 网盘未登录"
        case .server(let text): return "UC 网盘请求失败：\(text)"
        }
    }
}

protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionHTTPClient: HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error { continuation.resume(throwing: error) }
                else if let data, let response { continuation.resume(returning: (data, response)) }
                else { continuation.resume(throwing: URLError(.badServerResponse)) }
            }.resume()
        }
    }
}

struct UCDriveService: Sendable {
    let baseURL = URL(string: "https://pc-api.uc.cn/1/clouddrive/")!
    let accountURL = URL(string: "https://drive.uc.cn/account/info?fr=pc&platform=pc")!
    let qrcodeURL = URL(string: "https://api.open.uc.cn/cas/ajax/getTokenForQrcodeLogin?__dt=641254&__t=")!
    let userAgent = "uc-cloud-drive/1.8.7 Chrome/100.0.4896.160 Electron/18.3.5.16-b62cf9c50d Safari/537.36 Channel/ucpan_other_ch"
    let client: HTTPClient

    init(client: HTTPClient = URLSessionHTTPClient(session: .shared)) {
        self.client = client
    }

    private func makeRequest(url: URL, method: String = "GET", body: Data? = nil, headers: [String: String] = [:]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    func createQrcodeLogin() async throws -> UCDeviceCodeResponse {
        let url = qrcodeURL.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000))")
        let request = makeRequest(url: url)
        let (data, response) = try await client.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UCAuthError.server("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let result = json["result"] as? [String: Any] ?? json
        guard let deviceCode = (result["device_code"] as? String) ?? (result["deviceCode"] as? String),
              let qrContent = (result["qr_content"] as? String) ?? (result["qrContent"] as? String) ?? (result["verification_uri_complete"] as? String) else {
            throw UCAuthError.invalidResponse
        }
        let expiresIn = (result["expires_in"] as? TimeInterval) ?? (result["expiresIn"] as? TimeInterval) ?? 300
        let interval = (result["interval"] as? TimeInterval) ?? 5
        let openURL = URL(string: (result["open_url"] as? String) ?? "")
        return UCDeviceCodeResponse(deviceCode: deviceCode, qrContent: qrContent, expiresIn: expiresIn, interval: interval, openURL: openURL)
    }

    func pollQrcodeLogin(deviceCode: String) async throws -> UCCredential {
        let url = qrcodeURL.appendingPathComponent("poll")
        let body = try JSONSerialization.data(withJSONObject: ["device_code": deviceCode])
        let request = makeRequest(url: url, method: "POST", body: body)
        let (data, response) = try await client.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UCAuthError.server("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if let error = json["error"] as? String, error == "authorization_pending" {
            throw UCAuthError.server("pending")
        }
        if let token = (json["access_token"] as? String) ?? ((json["data"] as? [String: Any])?["access_token"] as? String) {
            let credential = try UCCredential(responseData: data)
            return credential
        }
        throw UCAuthError.invalidResponse
    }

    func refresh(credential: UCCredential) async throws -> UCCredential {
        let url = baseURL.appendingPathComponent("auth/refresh")
        let body = try JSONSerialization.data(withJSONObject: ["refresh_token": credential.refreshToken])
        let request = makeRequest(url: url, method: "POST", body: body)
        let (data, response) = try await client.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UCAuthError.server("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return try UCCredential(responseData: data, fallback: credential)
    }

    func accountInfo(credential: UCCredential) async throws -> UCCredential {
        let request = makeRequest(url: accountURL, headers: ["Authorization": credential.authorizationHeader])
        let (data, response) = try await client.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UCAuthError.server("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return try credential.mergingProfile(data)
    }
}
