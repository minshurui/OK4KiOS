import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol VodServiceProtocol {
    func home(page: Int) async throws -> VodResult
    func search(_ keyword: String, page: Int) async throws -> VodResult
    func category(id: String, page: Int) async throws -> VodResult
    func detail(id: String) async throws -> Vod
    func player(flag: String, id: String) async throws -> SpiderPlayback
    func types() async throws -> [VodClass]
}

extension VodServiceProtocol {
    func category(id: String, page: Int, filters: [String: String]) async throws -> VodResult {
        try await category(id: id, page: page)
    }
    func types() async throws -> [VodClass] { [] }
}

struct VodService: VodServiceProtocol {
    static let defaultBaseURL = URL(string: "https://tv.789056.xyz/api.php/provide/vod/")!
    let baseURL: URL
    private let client: APIClientProtocol
    private let decoder = JSONDecoder()

    init(baseURL: URL = VodService.defaultBaseURL, client: APIClientProtocol = APIClient()) {
        self.baseURL = baseURL
        self.client = client
    }

    func home(page: Int = 1) async throws -> VodResult {
        try await request([
            URLQueryItem(name: "ac", value: "detail"),
            URLQueryItem(name: "filter", value: "true"),
            URLQueryItem(name: "pg", value: String(page))
        ])
    }

    func search(_ keyword: String, page: Int = 1) async throws -> VodResult {
        try await request([
            URLQueryItem(name: "ac", value: "detail"),
            URLQueryItem(name: "wd", value: keyword),
            URLQueryItem(name: "pg", value: String(page))
        ])
    }

    func category(id: String, page: Int = 1) async throws -> VodResult {
        try await category(id: id, page: page, filters: [:])
    }

    func category(id: String, page: Int = 1, filters: [String: String]) async throws -> VodResult {
        var items = [
            URLQueryItem(name: "ac", value: "detail"),
            URLQueryItem(name: "t", value: id),
            URLQueryItem(name: "filter", value: "true"),
            URLQueryItem(name: "pg", value: String(page))
        ]
        for (key, value) in filters where !value.isEmpty {
            items.append(URLQueryItem(name: key, value: value))
        }
        return try await request(items)
    }

    func detail(id: String) async throws -> Vod {
        let result = try await request([URLQueryItem(name: "ac", value: "detail"), URLQueryItem(name: "ids", value: id)])
        guard let vod = result.list.first else { throw VodServiceError.emptyDetail }
        return vod
    }

    func types() async throws -> [VodClass] {
        let result = try await request([URLQueryItem(name: "ac", value: "list"), URLQueryItem(name: "t", value: "")])
        return result.types
    }

    func player(flag: String, id: String) async throws -> SpiderPlayback {
        SpiderPlayback(url: id)
    }

    private func request(_ queryItems: [URLQueryItem]) async throws -> VodResult {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw VodServiceError.invalidURL
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw VodServiceError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("OK4KiOS/0.1", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await client.data(for: request)
        return try decoder.decode(VodResult.self, from: data)
    }
}

enum VodServiceError: LocalizedError {
    case invalidURL
    case emptyDetail

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "接口地址无效"
        case .emptyDetail: return "接口没有返回影片详情"
        }
    }
}
