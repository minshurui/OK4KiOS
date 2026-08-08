import Foundation

/// 百度网盘会话：actor 管理 Cookie 凭据的持久化与验证。
/// 存储方式与 Android 一致：Cookie 持久化（非 OAuth token）。
actor BaiduSession {
    static let shared = BaiduSession()
    private let store: FishCredentialStore
    private let service: BaiduAuthService

    init(store: FishCredentialStore = FishSecureStore.shared, service: BaiduAuthService = BaiduAuthService()) {
        self.store = store
        self.service = service
    }

    func storedCredential() throws -> BaiduCredential? {
        guard let data = try store.data(for: "baidu") else { return nil }
        return try BaiduCredential(responseData: data)
    }

    func finishLogin(_ credential: BaiduCredential) async throws -> BaiduCredential {
        // Android 先持久化 Cookie，再获取用户信息。保留可用授权即使 profile 失败。
        try store.set(credential.raw, for: "baidu")
        do {
            let profiled = try await service.fetchUserInfo(cookie: credential.cookieHeader)
            try store.set(profiled.raw, for: "baidu")
            return profiled
        } catch {
            return credential
        }
    }

    func validatedCredential() async throws -> BaiduCredential {
        guard let stored = try storedCredential() else { throw BaiduAuthError.notLoggedIn }
        // 百度无 refresh_token，直接用 Cookie 验证用户信息
        do {
            let profiled = try await service.fetchUserInfo(cookie: stored.cookieHeader)
            try store.set(profiled.raw, for: "baidu")
            return profiled
        } catch {
            // Cookie 失效
            throw BaiduAuthError.notLoggedIn
        }
    }

    func logout() throws {
        try store.remove("baidu")
    }
}
