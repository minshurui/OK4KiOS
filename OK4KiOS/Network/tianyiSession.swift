import Foundation

/// 天翼云盘会话（actor + FishCredentialStore 注入）
actor TianyiSession {
    static let shared = TianyiSession()
    private let store: FishCredentialStore
    private let service: TianyiAuthService

    init(store: FishCredentialStore = FishSecureStore.shared, service: TianyiAuthService = TianyiAuthService()) {
        self.store = store
        self.service = service
    }

    func storedCredential() throws -> TianyiCredential? {
        guard let data = try store.data(for: "tianyi") else { return nil }
        return try TianyiCredential(responseData: data)
    }

    func finishLogin(_ credential: TianyiCredential) async throws -> TianyiCredential {
        // Android 持久化 token 后再拉取用户信息。保留可用授权即使 profile 不可用。
        try store.set(credential.raw, for: "tianyi")
        do {
            let profiled = try await service.getUserBriefInfo(cookie: "", sessionKey: credential.sessionKey)
            try store.set(profiled.raw, for: "tianyi")
            return profiled
        } catch {
            return credential
        }
    }

    func validatedCredential() async throws -> TianyiCredential {
        guard let stored = try storedCredential() else { throw TianyiAuthError.notLoggedIn }
        // 已有 sessionKey 时尝试刷新用户信息；失败则返回已存凭据（Android 语义）
        do {
            let profiled = try await service.getUserBriefInfo(cookie: "", sessionKey: stored.sessionKey)
            try store.set(profiled.raw, for: "tianyi")
            return profiled
        } catch {
            return stored
        }
    }

    func logout() throws {
        try store.remove("tianyi")
    }
}
