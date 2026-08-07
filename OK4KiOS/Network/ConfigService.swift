import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct ConfigService {
    private let client: APIClientProtocol

    init(client: APIClientProtocol = APIClient()) { self.client = client }

    func load(urlString: String) async throws -> [TVBoxSite] {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("OK4KiOS/0.2", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await client.data(for: request)
        return try JSONDecoder().decode(TVBoxConfig.self, from: data).sites
            .filter(\.isBrowsableVodSite)
            .filter { ($0.type == 0 || $0.type == 1) ? $0.apiURL != nil : ($0.type == 3 || $0.type == 4) }
    }
}
