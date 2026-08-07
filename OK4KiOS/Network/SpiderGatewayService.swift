import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct SpiderGatewayService: VodServiceProtocol {
    let site: TVBoxSite
    let gatewayURL: URL
    private let client: APIClientProtocol

    init(site: TVBoxSite, gatewayURL: URL, client: APIClientProtocol = APIClient()) {
        self.site = site
        self.gatewayURL = gatewayURL
        self.client = client
    }

    func home(page: Int) async throws -> VodResult {
        try await vod(operation: "home", payload: ["page": String(page), "filter": "1"])
    }

    func search(_ keyword: String, page: Int) async throws -> VodResult {
        try await vod(operation: "search", payload: ["keyword": keyword, "page": String(page)])
    }

    func category(id: String, page: Int) async throws -> VodResult {
        try await vod(operation: "category", payload: ["id": id, "page": String(page)])
    }

    func detail(id: String) async throws -> Vod {
        let result = try await vod(operation: "detail", payload: ["id": id])
        guard let item = result.list.first else { throw VodServiceError.emptyDetail }
        return item
    }

    func player(flag: String, id: String) async throws -> SpiderPlayback {
        let data = try await call(operation: "player", payload: ["flag": flag, "id": id])
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let rawURL = object?["url"] as? String, !rawURL.isEmpty else { throw SpiderError.noPlayableURL }
        let headers = object?["header"] as? [String: String] ?? object?["headers"] as? [String: String] ?? [:]
        return SpiderPlayback(url: externalizeGatewayURL(rawURL), headers: headers)
    }

    private func vod(operation: String, payload: [String: String]) async throws -> VodResult {
        let data = try await call(operation: operation, payload: payload)
        return try JSONDecoder().decode(VodResult.self, from: data)
    }

    private func call(operation: String, payload: [String: String]) async throws -> Data {
        var body: [String: Any] = ["operation": operation, "site": siteDictionary]
        body["payload"] = payload
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("OK4KiOS/0.4", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await client.data(for: request).0
    }

    private func externalizeGatewayURL(_ value: String) -> String {
        guard var components = URLComponents(string: value),
              ["127.0.0.1", "localhost", "0.0.0.0"].contains(components.host?.lowercased() ?? "") else { return value }
        components.scheme = gatewayURL.scheme
        components.host = gatewayURL.host
        components.port = gatewayURL.port
        return components.url?.absoluteString ?? value
    }

    private var endpoint: URL {
        if gatewayURL.path.hasSuffix("/api/spider") { return gatewayURL }
        return gatewayURL.appendingPathComponent("api/spider")
    }

    private var siteDictionary: [String: Any] {
        var result: [String: Any] = [
            "key": site.key,
            "name": site.name,
            "type": site.type,
            "api": site.api,
            "jar": site.jar,
            "header": site.headers
        ]
        if let ext = site.ext, let data = ext.encodedString.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) {
            result["ext"] = object
        }
        return result
    }
}
