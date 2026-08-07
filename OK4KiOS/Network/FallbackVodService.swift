import Foundation

/// Tries the native iOS implementation first and transparently falls back to
/// an Android Spider gateway when a site needs its original JAR implementation.
struct FallbackVodService: VodServiceProtocol {
    let primary: VodServiceProtocol
    let fallback: VodServiceProtocol

    func home(page: Int) async throws -> VodResult {
        try await attempt { try await primary.home(page: page) } fallback: { try await fallback.home(page: page) }
    }

    func search(_ keyword: String, page: Int) async throws -> VodResult {
        try await attempt { try await primary.search(keyword, page: page) } fallback: { try await fallback.search(keyword, page: page) }
    }

    func category(id: String, page: Int) async throws -> VodResult {
        try await attempt { try await primary.category(id: id, page: page) } fallback: { try await fallback.category(id: id, page: page) }
    }

    func detail(id: String) async throws -> Vod {
        try await attempt { try await primary.detail(id: id) } fallback: { try await fallback.detail(id: id) }
    }

    func player(flag: String, id: String) async throws -> SpiderPlayback {
        try await attempt { try await primary.player(flag: flag, id: id) } fallback: { try await fallback.player(flag: flag, id: id) }
    }

    private func attempt<T>(_ primaryCall: () async throws -> T, fallback fallbackCall: () async throws -> T) async throws -> T {
        do { return try await primaryCall() }
        catch { return try await fallbackCall() }
    }
}
