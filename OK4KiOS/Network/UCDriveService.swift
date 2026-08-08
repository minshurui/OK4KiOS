import Foundation

struct UCDeviceCodeResponse: Equatable, Sendable {
    let token: String
    let qrcode: String
    let qrSign: String
    let expiresIn: TimeInterval
    let interval: TimeInterval

    /// 轮询会话打包：qrcode|qr_sign
    var pollKey: String { "\(qrcode)|\(qrSign)" }
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
    case pending
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

    init(client: HTTPClient = URLSessionHTTPClient()) {
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

    private let casBase = "https://api.open.uc.cn/cas/ajax"

    private func firstString(_ objects: [[String: Any]], keys: [String]) -> String? {
        for object in objects {
            for key in keys {
                if let value = object[key] as? String, !value.isEmpty { return value }
            }
        }
        return nil
    }

    /// CAS 三步扫码：1) getTokenForQrcodeLogin 取 token → 2) getQrcodeLogin?token= 取 qrcode+qr_sign
    func createQrcodeLogin() async throws -> UCDeviceCodeResponse {
        let ts = "\(Int(Date().timeIntervalSince1970 * 1000))"
        // step 1: token
        let tokenURL = URL(string: "\(casBase)/getTokenForQrcodeLogin?__dt=641254&__t=\(ts)")!
        let (data1, _) = try await client.data(for: makeRequest(url: tokenURL))
        let json1 = try JSONSerialization.jsonObject(with: data1) as? [String: Any] ?? [:]
        let dataObj1 = json1["data"] as? [String: Any] ?? [:]
        let members = dataObj1["members"] as? [String: Any] ?? [:]
        guard let token = firstString([dataObj1, members], keys: ["token"]), !token.isEmpty else {
            throw UCAuthError.invalidResponse
        }
        // step 2: qrcode
        let qrURL = URL(string: "\(casBase)/getQrcodeLogin?token=\(token)")!
        let (data2, _) = try await client.data(for: makeRequest(url: qrURL))
        let json2 = try JSONSerialization.jsonObject(with: data2) as? [String: Any] ?? [:]
        let dataObj2 = json2["data"] as? [String: Any] ?? [:]
        guard let qrcode = firstString([dataObj2], keys: ["qrcode", "login_url"]), !qrcode.isEmpty else {
            throw UCAuthError.invalidResponse
        }
        let qrSign = firstString([dataObj2], keys: ["qr_sign"]) ?? ""
        return UCDeviceCodeResponse(token: token, qrcode: qrcode, qrSign: qrSign, expiresIn: 180, interval: 3)
    }

    /// 轮询：GET /cas/ajax/loginByQrcode?qrcode=..&qr_sign=.. 直到 status==1（拿 cookie）
    func pollQrcodeLogin(pollKey: String) async throws -> UCCredential {
        let parts = pollKey.split(separator: "|")
        guard parts.count == 2, let qrcode = parts.first, let sign = parts.last else {
            throw UCAuthError.invalidResponse
        }
        let encodedQR = qrcode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? String(qrcode)
        let signEncoded = sign.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? String(sign)
        let url = URL(string: "\(casBase)/loginByQrcode?qrcode=\(encodedQR)&qr_sign=\(signEncoded)")!
        let (data, _) = try await client.data(for: makeRequest(url: url))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let dataObj = json["data"] as? [String: Any] ?? [:]
        let status = (dataObj["status"] as? Int) ?? -1
        if status == 1 {
            // 成功：cookie + nickname
            let cookie = firstString([dataObj], keys: ["cookie", "Cookie"]) ?? ""
            let nickname = firstString([dataObj], keys: ["nickname", "nick_name", "display_name"]) ?? ""
            let payload: [String: Any] = ["cookie": cookie, "display_name": nickname, "status": 1]
            let credentialData = try JSONSerialization.data(withJSONObject: payload)
            let credential = try UCCredential(responseData: credentialData)
            if !cookie.isEmpty {
                // 保存 cookie 供业务读取（未知字段保留）
                var merged = try JSONSerialization.jsonObject(with: credential.raw) as? [String: Any] ?? [:]
                merged["uc_cookie"] = cookie
                return try UCCredential(responseData: JSONSerialization.data(withJSONObject: merged))
            }
            return credential
        }
        if status != 0 && status != 2000001 && status != 2000002 {
            throw UCAuthError.server("UC扫码失败或已取消（status=\(status)）")
        }
        throw UCAuthError.pending
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
