import Foundation

/// 移动云盘（139）网络层。已取证端点（Docs/NetdiskEndpointsEvidence.md §9）：
/// 用户 `https://user-njs.yun.139.com/user/getUser`、配额 `/user/disk/quota/detail`、
/// 列表 `/v1.2/queryContentList`、扫码页 `https://yun.139.com/w/#/qrcLogin?sID=`。
/// 扫码 API 细节（创建/轮询）尚未从 smali 完整取证 → 扫码登录诚实 pending，凭证导入可用。
struct YiDongCredential: Equatable, Sendable {
    let raw: Data
    let authorization: String
    let userID: String
    let name: String
    let phone: String

    var displayName: String? { name.nonempty ?? phone.nonempty ?? userID.nonempty }

    init(responseData: Data, fallback: YiDongCredential? = nil) throws {
        let response = try Self.dictionary(responseData)
        let previous = try fallback.map { try Self.dictionary($0.raw) } ?? [:]
        var merged = Self.deepMerge(previous, response)
        let data = response["data"] as? [String: Any] ?? response
        let prevData = previous["data"] as? [String: Any] ?? previous

        func value(_ keys: [String], fallbackValue: String = "") -> String {
            Self.firstString(in: [data, response, prevData, previous], keys: keys) ?? fallbackValue
        }
        authorization = value(["authorization", "Authorization", "token", "access_token", "cookie"], fallbackValue: fallback?.authorization ?? "")
        userID = value(["userID", "user_id", "userId", "sID"], fallbackValue: fallback?.userID ?? "")
        name = value(["name", "nickname", "realName"], fallbackValue: fallback?.name ?? "")
        phone = value(["phone", "mobile", "phone_number"], fallbackValue: fallback?.phone ?? "")
        guard !authorization.isEmpty else { throw YiDongError.invalidResponse }

        merged["authorization"] = authorization
        if !userID.isEmpty { merged["userID"] = userID }
        if !name.isEmpty { merged["name"] = name }
        if !phone.isEmpty { merged["phone"] = phone }
        raw = try JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys])
    }

    func mergingProfile(_ responseData: Data) throws -> YiDongCredential {
        try YiDongCredential(responseData: responseData, fallback: self)
    }

    private static func dictionary(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YiDongError.invalidResponse
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

enum YiDongError: LocalizedError, Equatable {
    case invalidResponse
    case notLoggedIn
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "移动云盘响应格式不正确"
        case .notLoggedIn: return "移动云盘未登录"
        case .server(let message): return message
        }
    }
}

protocol YiDongHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: YiDongHTTPClient {}

struct YiDongDriveService: Sendable {
    var client: any YiDongHTTPClient
    let userBase = URL(string: "https://user-njs.yun.139.com")!
    let scanPage = "https://yun.139.com/w/#/qrcLogin"

    init(client: any YiDongHTTPClient = URLSession.shared) {
        self.client = client
    }

    private func makeRequest(url: URL, method: String = "GET", body: Data? = nil, headers: [String: String] = [:]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    func userInfo(credential: YiDongCredential) async throws -> YiDongCredential {
        let url = userBase.appendingPathComponent("user/getUser")
        let request = makeRequest(url: url, headers: ["Authorization": credential.authorization])
        let (data, response) = try await client.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw YiDongError.server("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return try credential.mergingProfile(data)
    }

    func quotaDetail(credential: YiDongCredential) async throws -> Data {
        let url = userBase.appendingPathComponent("user/disk/quota/detail")
        let request = makeRequest(url: url, headers: ["Authorization": credential.authorization])
        let (data, response) = try await client.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw YiDongError.server("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return data
    }

    /// 扫码登录协议未完整取证（qrcLogin 为网页 hash 端点）；凭证导入（Authorization/Cookie）已支持。
    func scanLoginIsPending() -> Bool { true }
}
