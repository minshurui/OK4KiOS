import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct ConfigService {
    private let client: APIClientProtocol

    init(client: APIClientProtocol = APIClient()) { self.client = client }

    func load(urlString: String) async throws -> [TVBoxSite] {
        let config = try await fetch(urlString: urlString)
        return config.sites
            .filter { ($0.type == 0 || $0.type == 1) ? $0.apiURL != nil : ($0.type == 3 || $0.type == 4) }
    }

    /// Returns live source names and URLs declared by a TVBox config's `lives` array.
    func loadLives(urlString: String) async throws -> [String: String] {
        let config = try await fetch(urlString: urlString)
        var result: [String: String] = [:]
        for live in config.lives {
            guard let name = live.name, !name.isEmpty, let url = live.url, !url.isEmpty else { continue }
            result[name] = url
        }
        return result
    }

    private func fetch(urlString: String) async throws -> TVBoxConfig {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("OK4KiOS/0.5", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await client.data(for: request)
        return try JSONDecoder().decode(TVBoxConfig.self, from: decryptFishExts(in: data))
    }

    /// FishGuard extDe envelopes are decrypted by the native Go bridge before
    /// TVBoxSite decoding, so downstream adapters receive the original JSON ext.
    private func decryptFishExts(in data: Data) throws -> Data {
        guard GoSpiderBridge.isAvailable,
              var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var sites = root["sites"] as? [[String: Any]] else { return data }
        var changed = false
        for index in sites.indices {
            guard let encoded = sites[index]["ext"] as? String,
                  encoded.hasPrefix("A"),
                  let decrypted = try? GoSpiderBridge.decryptExt(encoded),
                  let value = try? JSONSerialization.jsonObject(with: decrypted) else { continue }
            sites[index]["ext"] = value
            changed = true
        }
        guard changed else { return data }
        root["sites"] = sites
        return try JSONSerialization.data(withJSONObject: root)
    }
}
