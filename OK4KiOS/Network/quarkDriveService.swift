import Foundation

// MARK: - 夸克网盘网络层
// 端点取证来源：Docs/NetdiskEndpointsEvidence.md 夸克小节 + Docs/quark-strings.txt / Docs/quark-calls.txt
// 基址 https://drive.quark.cn/1/clouddrive/；账号 https://pan.quark.cn/account/info?fr=pc&platform=pc
// 扫码 https://uop.quark.cn/cas/ajax/getTokenForQrcodeLogin（机制同 UC）
// 分享 token .../share/sharepage/token?__t=；下载 token https://drive-social-api.quark.cn/1/clouddrive/chat/conv/file/acquire_dl_token?pr=ucpro&fr=pc&sys=win32&ve=3.15.0
// 转存 .../chat/conv/msg/batch_send?...；会员 .../member?...；下载 https://drive-pc.quark.cn/1/clouddrive/file/download?pr=ucpro&fr=pc
// 分享正则 https://pan\.quark\.cn/s/([^\\|#/?]+)

struct QuarkDeviceAuthorization: Equatable, Sendable {
    let deviceCode: String
    let verificationURL: URL
    let expiresIn: TimeInterval
    let interval: TimeInterval
}

struct QuarkCredential: Equatable, Sendable {
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

    init(responseData: Data, fallback: QuarkCredential? = nil) throws {
        let response = try Self.dictionary(responseData)
        let previous = try fallback.map { try Self.dictionary($0.raw) } ?? [:]
        var merged = Self.deepMerge(previous, response)
        let responseDataObject = response["data"] as? [String: Any] ?? response
        let previousDataObject = previous["data"] as? [String: Any] ?? previous

        func value(_ keys: [String], fallbackValue: String = "") -> String {
            Self.firstString(in: [responseDataObject, response, previousDataObject, previous], keys: keys) ?? fallbackValue
        }

        accessToken = value(["access_token", "accessToken", "st", "token"], fallbackValue: fallback?.accessToken ?? "")
        refreshToken = value(["refresh_token", "refreshToken", "refresh_token"], fallbackValue: fallback?.refreshToken ?? "")
        tokenType = value(["token_type", "tokenType"], fallbackValue: fallback?.tokenType ?? "Bearer").nonempty ?? "Bearer"
        subject = value(["sub", "uid", "user_id", "userid"], fallbackValue: fallback?.subject ?? "")
        name = value(["name", "nickname", "nick_name", "display_name"], fallbackValue: fallback?.name ?? "")
        picture = value(["picture", "avatar", "avatar_url"], fallbackValue: fallback?.picture ?? "")
        phone = value(["phone_number", "phone", "mobile"], fallbackValue: fallback?.phone ?? "")
        kaiserFolder = value(["kaiser_folder", "default_folder"], fallbackValue: fallback?.kaiserFolder ?? "")
        guard !accessToken.isEmpty else { throw QuarkAuthError.invalidResponse }

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

    func mergingProfile(_ responseData: Data) throws -> QuarkCredential {
        try QuarkCredential(responseData: responseData, fallback: self)
    }

    private static func dictionary(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuarkAuthError.invalidResponse
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

enum QuarkPollResult: Equatable, Sendable {
    case pending
    case authorized(QuarkCredential)
}

enum QuarkAuthError: LocalizedError, Equatable {
    case invalidResponse
    case server(String)
    case timeout
    case cancelled
    case missingRefreshToken
    case notLoggedIn

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "夸克授权响应无效"
        case .server(let text): return "夸克授权失败：\(text)"
        case .timeout: return "夸克扫码已超时"
        case .cancelled: return "夸克扫码已取消"
        case .missingRefreshToken: return "缺少 refresh token，请重新扫码登录"
        case .notLoggedIn: return "夸克网盘未登录，请先扫码登录"
        }
    }
}

protocol QuarkHTTPClientProtocol {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct QuarkHTTPClient: QuarkHTTPClientProtocol {
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

struct QuarkAuthService {
    static let qrcodeBase = "https://uop.quark.cn/cas/ajax/getTokenForQrcodeLogin"
    static let accountBase = "https://pan.quark.cn/account/info?fr=pc&platform=pc"
    static let driveBase = "https://drive.quark.cn/1/clouddrive/"
    private let client: QuarkHTTPClientProtocol

    init(client: QuarkHTTPClientProtocol = QuarkHTTPClient()) { self.client = client }

    func begin() async throws -> QuarkDeviceAuthorization {
        // 扫码创建端点：https://uop.quark.cn/cas/ajax/getTokenForQrcodeLogin（机制同 UC）
        // 请求体/响应字段取证自 Docs/quark-calls.txt；若字段不足则诚实抛 protocolPending
        // 当前取证：Android 使用 GET 请求，带 __t 时间戳参数
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        var components = URLComponents(string: Self.qrcodeBase)!
        components.queryItems = [URLQueryItem(name: "__t", value: String(timestamp))]
        guard let url = components.url else { throw QuarkAuthError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let result = try await client.data(for: request)
        guard result.1.statusCode == 200 else {
            throw QuarkAuthError.server("HTTP \(result.1.statusCode)")
        }
        let root = try dictionary(result.0)
        // 取证字段：data.qr_code / data.qr_token / data.expires_in / data.interval
        // 若字段不足，诚实抛 protocolPending
        guard let data = root["data"] as? [String: Any] else {
            throw QuarkAuthError.invalidResponse
        }
        guard let qrCode = firstString(data, root, keys: ["qr_code", "qrCode", "qr_content", "qrContent", "url"]),
              let qrToken = firstString(data, root, keys: ["qr_token", "qrToken", "token", "device_code", "deviceCode"]),
              let url = URL(string: qrCode) else {
            throw FishDriveError.protocolPending("夸克扫码创建响应字段不足：已取证端点 uop.quark.cn/cas/ajax/getTokenForQrcodeLogin，但响应缺少 qr_code/qr_token 字段")
        }
        return .init(deviceCode: qrToken, verificationURL: url,
                     expiresIn: number(data["expires_in"] ?? data["expiresIn"]) ?? 180,
                     interval: max(1, number(data["interval"]) ?? 3))
    }

    func poll(deviceCode: String) async throws -> QuarkPollResult {
        // 轮询端点：https://uop.quark.cn/cas/ajax/getTokenForQrcodeLogin（同创建，带 qr_token 参数）
        // 轮询间隔 3s，超时 180s（与 Android 一致）
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        var components = URLComponents(string: Self.qrcodeBase)!
        components.queryItems = [
            URLQueryItem(name: "__t", value: String(timestamp)),
            URLQueryItem(name: "qr_token", value: deviceCode)
        ]
        guard let url = components.url else { throw QuarkAuthError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let result = try await client.data(for: request)
        let root = try dictionary(result.0)
        // 成功判定：data.status == "confirmed" 或 data.token 存在
        // 若字段不足，诚实抛 protocolPending
        if let data = root["data"] as? [String: Any] {
            if let status = data["status"] as? String, status == "confirmed" {
                // 构造凭据：从 data 中提取 token 字段
                let credentialData = try JSONSerialization.data(withJSONObject: data, options: [])
                let credential = try QuarkCredential(responseData: credentialData)
                return .authorized(credential)
            }
            if let token = data["token"] as? String, !token.isEmpty {
                let credentialData = try JSONSerialization.data(withJSONObject: data, options: [])
                let credential = try QuarkCredential(responseData: credentialData)
                return .authorized(credential)
            }
        }
        // 未确认：pending
        return .pending
    }

    func profile(for credential: QuarkCredential) async throws -> QuarkCredential {
        // 账号端点：https://pan.quark.cn/account/info?fr=pc&platform=pc
        guard let url = URL(string: Self.accountBase) else { throw QuarkAuthError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(credential.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let result = try await client.data(for: request)
        guard result.1.statusCode == 200 else {
            throw QuarkAuthError.server("HTTP \(result.1.statusCode)")
        }
        return try credential.mergingProfile(result.0)
    }

    func refresh(_ credential: QuarkCredential) async throws -> QuarkCredential {
        // 刷新端点：https://drive.quark.cn/1/clouddrive/...（取证自 quark-calls.txt）
        // 若刷新端点字段不足，诚实抛 protocolPending
        throw FishDriveError.protocolPending("夸克 refresh_token 刷新端点字段取证不足：已定位 drive.quark.cn/1/clouddrive/ 基址，但 refresh 请求体/响应字段待 smali 方法级分析")
    }

    private func dictionary(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuarkAuthError.invalidResponse
        }
        return value
    }

    private func firstString(_ objects: [String: Any]..., keys: [String]) -> String? {
        for object in objects {
            for key in keys {
                if let value = object[key] as? String, let value = value.nonempty { return value }
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
