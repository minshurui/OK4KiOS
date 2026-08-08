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

/// 天翼云盘扫码会话（创建二维码响应）
struct TianyiQRCodeSession: Equatable, Sendable {
    let qrContent: String
    let sessionKey: String
    let shortToken: String
    let appId: String
    let interval: TimeInterval
    let timeout: TimeInterval
}

/// 天翼云盘扫码轮询响应
struct TianyiQRCodePollResponse: Equatable, Sendable {
    let result: Int
    let token: String?
    let redirectURL: String?
    let message: String?
    let errorDescription: String?
    
    var isPending: Bool { result == 1 || result == 2 }
    var isExpired: Bool { result == 4 }
    var isSuccess: Bool { result == 0 && token != nil }
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
                if let value = object[key] as? String, !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private static func deepMerge(_ base: [String: Any], _ override: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in override {
            if let dict = value as? [String: Any], let baseDict = result[key] as? [String: Any] {
                result[key] = deepMerge(baseDict, dict)
            } else {
                result[key] = value
            }
        }
        return result
    }
}

/// 天翼云盘认证错误
enum TianyiAuthError: Error, LocalizedError {
    case invalidResponse
    case notLoggedIn
    case networkError(String)
    case serverError(Int, String?)
    case qrCodeExpired
    case qrCodePending
    case qrCodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "响应格式无效"
        case .notLoggedIn:
            return "未登录"
        case .networkError(let message):
            return "网络错误: \(message)"
        case .serverError(let code, let message):
            return "服务器错误 (\(code)): \(message ?? "未知错误")"
        case .qrCodeExpired:
            return "二维码已过期，请重新扫码"
        case .qrCodePending:
            return "等待扫码确认..."
        case .qrCodeFailed(let message):
            return "扫码失败: \(message)"
        }
    }
}

/// 天翼云盘认证服务
struct TianyiAuthService {
    private let baseURL = URL(string: "https://api.cloud.189.cn")!
    private let appId = "8027001086180899"
    private let channelId = "web_cloud.189.cn"
    private let clientType = "TELEPC"
    private let version = "6.2"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - 扫码登录

    /// 创建二维码（对应 Android: GET /open/user/getQrCode.action）
    func createQRCode() async throws -> TianyiQRCodeSession {
        var components = URLComponents(url: baseURL.appendingPathComponent("/open/user/getQrCode.action"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "appId", value: appId),
            URLQueryItem(name: "clientType", value: clientType),
            URLQueryItem(name: "version", value: version),
            URLQueryItem(name: "channelId", value: channelId)
        ]
        
        guard let url = components.url else {
            throw TianyiAuthError.networkError("URL 构造失败")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TianyiAuthError.networkError("无效响应")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw TianyiAuthError.serverError(httpResponse.statusCode, String(data: data, encoding: .utf8))
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TianyiAuthError.invalidResponse
        }
        
        guard let result = json["result"] as? Int, result == 0 else {
            let message = json["msg"] as? String ?? "未知错误"
            throw TianyiAuthError.qrCodeFailed(message)
        }
        
        guard let qrContent = json["qrCode"] as? String,
              let sessionKey = json["sessionKey"] as? String,
              let shortToken = json["shortToken"] as? String else {
            throw TianyiAuthError.invalidResponse
        }
        
        return TianyiQRCodeSession(
            qrContent: qrContent,
            sessionKey: sessionKey,
            shortToken: shortToken,
            appId: appId,
            interval: 3,
            timeout: 180
        )
    }

    /// 轮询扫码状态（对应 Android: POST /open/user/qrCodeLogin.action）
    func pollQRCodeLogin(sessionKey: String, shortToken: String, appId: String) async throws -> TianyiQRCodePollResponse {
        let url = baseURL.appendingPathComponent("/open/user/qrCodeLogin.action")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let formData = [
            "appId": appId,
            "sessionKey": sessionKey,
            "shortToken": shortToken
        ]
        
        let bodyString = formData
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TianyiAuthError.networkError("无效响应")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw TianyiAuthError.serverError(httpResponse.statusCode, String(data: data, encoding: .utf8))
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TianyiAuthError.invalidResponse
        }
        
        let result = json["result"] as? Int ?? -1
        let token = json["token"] as? String
        let redirectURL = json["redirectUrl"] as? String
        let message = json["msg"] as? String
        let errorDescription = json["errorDesc"] as? String
        
        return TianyiQRCodePollResponse(
            result: result,
            token: token,
            redirectURL: redirectURL,
            message: message,
            errorDescription: errorDescription
        )
    }

    /// 完成登录：用 token 换取会话 Cookie（对应 Android: GET /open/user/getUserBriefInfo.action?token=...）
    func finishLogin(token: String) async throws -> (cookie: String, userInfo: [String: Any]) {
        var components = URLComponents(url: baseURL.appendingPathComponent("/open/user/getUserBriefInfo.action"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        
        guard let url = components.url else {
            throw TianyiAuthError.networkError("URL 构造失败")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TianyiAuthError.networkError("无效响应")
        }
        
        // 提取 Set-Cookie
        let cookies = httpResponse.value(forHTTPHeaderField: "Set-Cookie") ?? ""
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw TianyiAuthError.serverError(httpResponse.statusCode, String(data: data, encoding: .utf8))
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TianyiAuthError.invalidResponse
        }
        
        return (cookies, json)
    }

    /// 获取用户简要信息（用于状态校验）
    func getUserBriefInfo(cookie: String, sessionKey: String?) async throws -> [String: Any] {
        let url = baseURL.appendingPathComponent("/api/portal/v2/getUserBriefInfo.action")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        if let sessionKey {
            request.setValue(sessionKey, forHTTPHeaderField: "SessionKey")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TianyiAuthError.networkError("无效响应")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw TianyiAuthError.serverError(httpResponse.statusCode, String(data: data, encoding: .utf8))
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TianyiAuthError.invalidResponse
        }
        
        guard let result = json["result"] as? Int, result == 0 else {
            throw TianyiAuthError.notLoggedIn
        }
        
        return json
    }
}

// MARK: - 天翼云盘会话管理
struct TianyiSession {
    static let shared = TianyiSession()
    
    private let store: FishCredentialStore
    private let auth: TianyiAuthService
    
    init(store: FishCredentialStore = FishSecureStore.shared, auth: TianyiAuthService = TianyiAuthService()) {
        self.store = store
        self.auth = auth
    }
    
    private var credentialKey: String { "tianyi" }
    
    func saveCredential(_ credential: TianyiCredential) throws {
        try store.set(credential.raw, for: credentialKey)
    }
    
    func loadCredential() throws -> TianyiCredential? {
        guard let data = try store.data(for: credentialKey) else { return nil }
        return try TianyiCredential(responseData: data)
    }
    
    func validatedCredential() async throws -> TianyiCredential {
        guard let credential = try loadCredential() else {
            throw TianyiAuthError.notLoggedIn
        }
        
        // 校验用户信息
        do {
            let userInfo = try await auth.getUserBriefInfo(cookie: credential.sessionKey, sessionKey: credential.sessionKey)
            let updated = try credential.mergingProfile(try JSONSerialization.data(withJSONObject: userInfo))
            try saveCredential(updated)
            return updated
        } catch {
            throw TianyiAuthError.notLoggedIn
        }
    }
    
    func logout() async throws {
        try store.delete(for: credentialKey)
    }
}
