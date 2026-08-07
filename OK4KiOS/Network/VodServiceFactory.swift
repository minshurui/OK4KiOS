import Foundation

enum VodServiceFactory {
    static func current(settings: AppSettings = .shared) -> VodServiceProtocol {
        guard let site = settings.selectedSite else {
            return VodService(baseURL: settings.vodAPIURL ?? VodService.defaultBaseURL)
        }
        if site.type == 0 || site.type == 1 {
            return VodService(baseURL: site.apiURL ?? settings.vodAPIURL ?? VodService.defaultBaseURL)
        }
        if let service = try? NativeSpiderService(site: site) { return service }
        if let gateway = URL(string: settings.spiderGateway), ["http", "https"].contains(gateway.scheme?.lowercased() ?? "") {
            return SpiderGatewayService(site: site, gatewayURL: gateway)
        }
        return UnavailableVodService(error: SpiderError.gatewayRequired(site.name))
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
