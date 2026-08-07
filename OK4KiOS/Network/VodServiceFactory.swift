import Foundation

enum VodServiceFactory {
    static func current(settings: AppSettings = .shared) -> VodServiceProtocol {
        guard let site = settings.selectedSite else {
            let custom = TVBoxSite(key: "manual", name: "手动接口", type: settings.vodAPIType, api: settings.vodAPI)
            return TVBoxAPIService(site: custom)
        }
        if site.type == 0 || site.type == 1 {
            return TVBoxAPIService(site: site)
        }
        // Go engine (c-archive) handles wogg and type 4 rule sites when linked.
        let isWogg = site.key.caseInsensitiveCompare("wogg") == .orderedSame || site.name.lowercased().contains("wogg")
        if GoSpiderBridge.isAvailable, isWogg || site.type == 4 {
            return GoSiteAdapter(site: site)
        }
        let gateway = URL(string: settings.spiderGateway).flatMap {
            ["http", "https"].contains($0.scheme?.lowercased() ?? "") ? SpiderGatewayService(site: site, gatewayURL: $0) : nil
        }
        if let native = try? NativeSpiderService(site: site) {
            if let gateway { return FallbackVodService(primary: native, fallback: gateway) }
            return native
        }
        if let gateway { return gateway }
        return UnavailableVodService(error: SpiderError.nativeMigrationPending(site.name))
    }
}

private struct UnavailableVodService: VodServiceProtocol {
    let error: Error
    func home(page: Int) async throws -> VodResult { throw error }
    func search(_ keyword: String, page: Int) async throws -> VodResult { throw error }
    func category(id: String, page: Int) async throws -> VodResult { throw error }
    func detail(id: String) async throws -> Vod { throw error }
    func player(flag: String, id: String) async throws -> SpiderPlayback { throw error }
}
