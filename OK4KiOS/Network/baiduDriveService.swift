import Foundation

// MARK: - 百度网盘网络层
//
// 端点取证来源：Docs/NetdiskEndpointsEvidence.md 百度小节 + Docs/baidu-strings.txt / Docs/baidu-calls.txt
// Android 核心委托 C0243g + W0/A 类，登录方式：扫码登录 K2(17) + 手动 Cookie (r1)
// 存储方式：Cookie 持久化（非 OAuth token）
//
// 扫码协议端点（Go 参考实现）：
//   - 创建二维码 GET https://passport.baidu.com/v2/api/getqrcode?lp=pc&apiver=v3 -> {data:{img,sign}}
//   - 轮询 GET https://passport.baidu.com/v2/api/qrcode/{sign}?lp=pc&apiver=v3
//     status: 0 未扫 / 1 已扫待确认 / 2 已确认 / 3 过期
//   - 登录 GET https://passport.baidu.com/v3/api/login?sign=..&u=http://pan.baidu.com/disk/home
//     （重定向链写入 BDUSS）

// MARK: - 百度网盘凭据（Cookie 持久化）

struct BaiduCredential: Equatable, Sendable {
    let raw: Data
    let cookies: [String: String]
    let username: String
    let avatar: String
    let vipLevel: String

    var displayName: String? {
        username.nonempty
    }

    init(responseData: Data, fallback: BaiduCredential? = nil) throws {
        let response = try Self.dictionary(responseData)
        let previous = try fallback.map { try Self.dictionary($0.raw) } ?? [:]
        var merged = Self.deepMerge(previous, response)

        // 百度返回的用户信息字段（从 baidu-strings.txt 取证）
        let responseDataObject = response["data"] as? [String: Any] ?? response
        let previousDataObject = previous["data"] as? [String: Any] ?? previous

        func value(_ keys: [String], fallbackValue: String = "") -> String {
            Self.firstString(in: [responseDataObject, response, previousDataObject, previous], keys: keys) ?? fallbackValue
        }

        // Cookie 从请求头或响应中提取
        var cookieDict: [String: String] = [:]
        let cookieString = value(["cookie", "Cookie"])
        if !cookieString.isEmpty {
            for pair in cookieString.split(separator: ";") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    cookieDict[String(parts[0]).trimmingCharacters(in: .whitespaces)] = String(parts[1]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        // 也支持直接传入 cookie 字典
        if let cookieObj = responseDataObject["cookies"] as? [String: String] {
            cookieDict.merge(cookieObj) { _, new in new }
        }
        if let cookieObj = previousDataObject["cookies"] as? [String: String] {
            cookieDict.merge(cookieObj) { _, new in new }
        }

        cookies = cookieDict
        username = value(["username", "uname", "name", "nickname"], fallbackValue: fallback?.username ?? "")
        avatar = value(["avatar", "portrait", "picture"], fallbackValue: fallback?.avatar ?? "")
        vipLevel = value(["vip_level", "vipLevel", "vip"], fallbackValue: fallback?.vipLevel ?? "")

        guard !cookies.isEmpty else { throw BaiduAuthError.invalidResponse }

        // Canonical projections
        merged["cookies"] = cookies
        if !username.isEmpty { merged["username"] = username }
        if !avatar.isEmpty { merged["avatar"] = avatar }
        if !vipLevel.isEmpty { merged["vip_level"] = vipLevel }
        raw = try JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys])
    }

    init(cookieString: String, fallback: BaiduCredential? = nil) throws {
        var cookieDict: [String: String] = [:]
        for pair in cookieString.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                cookieDict[String(parts[0]).trimmingCharacters(in: .whitespaces)] = String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        }
        guard !cookieDict.isEmpty else { throw BaiduAuthError.invalidResponse }
        
        // 构造一个最小响应，让 init(responseData:) 能解析
        let minimalResponse: [String: Any] = ["cookies": cookieDict]
        let data = try JSONSerialization.data(withJSONObject: minimalResponse)
        try self.init(responseData: data, fallback: fallback)
    }

    var cookieHeader: String {
        cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }

    private static func dictionary(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BaiduAuthError.invalidResponse
        }
        return value
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

    private static func firstString(in sources: [[String: Any]], keys: [String]) -> String? {
        for source in sources {
            for key in keys {
                if let value = source[key] as? String, !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }
}

// MARK: - 百度扫码会话

struct BaiduQRCodeSession: Equatable, Sendable {
    let sign: String
    let qrImage: String
    let interval: TimeInterval
    let timeout: TimeInterval
    
    init(sign: String, qrImage: String, interval: TimeInterval = 3, timeout: TimeInterval = 180) {
        self.sign = sign
        self.qrImage = qrImage
        self.interval = interval
        self.timeout = timeout
    }
    
    init?(dictionary: [String: Any]) {
        guard let sign = dictionary["sign"] as? String,
              let qrImage = dictionary["qrImage"] as? String else {
            return nil
        }
        self.sign = sign
        self.qrImage = qrImage
        self.interval = (dictionary["interval"] as? TimeInterval) ?? 3
        self.timeout = (dictionary["timeout"] as? TimeInterval) ?? 180
    }
    
    var dictionary: [String: Any] {
        ["sign": sign, "qrImage": qrImage, "interval": interval, "timeout": timeout]
    }
}

// MARK: - 百度认证错误

enum BaiduAuthError: Error, LocalizedError {
    case invalidResponse
    case networkError(String)
    case qrExpired
    case qrPending
    case qrConfirmed
    case noBDUSSCookie
    case invalidCookie
    case notLoggedIn
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "百度响应格式无效"
        case .networkError(let message):
            return "网络错误: \(message)"
        case .qrExpired:
            return "二维码已过期，请重新扫码"
        case .qrPending:
            return "等待扫码确认..."
        case .qrConfirmed:
            return "扫码已确认，正在登录..."
        case .noBDUSSCookie:
            return "未获取到 BDUSS Cookie"
        case .invalidCookie:
            return "Cookie 无效"
        case .notLoggedIn:
            return "未登录"
        }
    }
}

// MARK: - 百度 HTTP 客户端

protocol BaiduHTTPClientProtocol {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct BaiduHTTPClient: BaiduHTTPClientProtocol {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let result: (Data, URLResponse) = try await URLSession.shared.data(for: request)
        guard let http = result.1 as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (result.0, http)
    }
}

// MARK: - 百度认证服务

struct BaiduAuthService {
    private let passportBase = "https://passport.baidu.com"
    private let panBase = "https://pan.baidu.com"
    private let client: BaiduHTTPClientProtocol
    
    init(client: BaiduHTTPClientProtocol = BaiduHTTPClient()) {
        self.client = client
    }
    
    // MARK: - 创建二维码
    
    func createQRCode() async throws -> BaiduQRCodeSession {
        let url = URL(string: "\(passportBase)/v2/api/getqrcode?lp=pc&apiver=v3")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await client.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw BaiduAuthError.networkError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errno = json["errno"] as? Int, errno == 0,
              let dataObj = json["data"] as? [String: Any],
              let img = dataObj["img"] as? String,
              let sign = dataObj["sign"] as? String else {
            throw BaiduAuthError.invalidResponse
        }
        
        return BaiduQRCodeSession(sign: sign, qrImage: img)
    }
    
    // MARK: - 轮询二维码状态
    
    enum QRCodeStatus: Equatable {
        case pending
        case confirmed
        case expired
        case unknown(Int)
    }
    
    func pollQRCode(sign: String) async throws -> QRCodeStatus {
        let url = URL(string: "\(passportBase)/v2/api/qrcode/\(sign)?lp=pc&apiver=v3")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await client.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw BaiduAuthError.networkError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let status = dataObj["status"] as? Int else {
            throw BaiduAuthError.invalidResponse
        }
        
        switch status {
        case 0, 1:
            return .pending
        case 2:
            return .confirmed
        case 3:
            return .expired
        default:
            return .unknown(status)
        }
    }
    
    // MARK: - 完成登录（获取 BDUSS Cookie）
    
    func finishLogin(sign: String) async throws -> BaiduCredential {
        let encodedURL = "http%3A%2F%2Fpan.baidu.com%2Fdisk%2Fhome"
        let url = URL(string: "\(passportBase)/v3/api/login?sign=\(sign)&u=\(encodedURL)&apiver=v3&lp=pc")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // 不跟随重定向，手动收集 Set-Cookie
        let (_, response) = try await client.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BaiduAuthError.networkError("无效响应")
        }
        
        var allCookies: [String: String] = [:]
        
        // 收集当前响应的 Set-Cookie
        if let setCookies = http.value(forHTTPHeaderField: "Set-Cookie") {
            parseCookies(setCookies, into: &allCookies)
        }
        
        // 如果有重定向，跟随并收集
        if let location = http.value(forHTTPHeaderField: "Location"),
           let redirectURL = URL(string: location, relativeTo: url) {
            var redirectRequest = URLRequest(url: redirectURL)
            redirectRequest.httpMethod = "GET"
            redirectRequest.setValue(allCookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
            
            let (_, redirectResponse) = try await client.data(for: redirectRequest)
            if let redirectHTTP = redirectResponse as? HTTPURLResponse {
                if let setCookies = redirectHTTP.value(forHTTPHeaderField: "Set-Cookie") {
                    parseCookies(setCookies, into: &allCookies)
                }
            }
        }
        
        guard let bduss = allCookies["BDUSS"], !bduss.isEmpty else {
            throw BaiduAuthError.noBDUSSCookie
        }
        
        // 构造凭据
        let cookieString = allCookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        return try BaiduCredential(cookieString: cookieString)
    }
    
    private func parseCookies(_ cookieHeader: String, into dict: inout [String: String]) {
        for pair in cookieHeader.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                dict[key] = value
            }
        }
    }
    
    // MARK: - 获取用户信息
    
    func fetchUserInfo(cookie: String) async throws -> BaiduCredential {
        let url = URL(string: "\(panBase)/api/user/getinfo")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("https://pan.baidu.com/", forHTTPHeaderField: "Referer")
        
        let (data, response) = try await client.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw BaiduAuthError.networkError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errno = json["errno"] as? Int, errno == 0 else {
            throw BaiduAuthError.invalidCookie
        }
        
        // 合并用户信息
        var userInfo = json
        userInfo["cookie"] = cookie
        let userData = try JSONSerialization.data(withJSONObject: userInfo)
        return try BaiduCredential(responseData: userData)
    }
}
