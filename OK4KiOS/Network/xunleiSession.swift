import Foundation

actor XunleiSession {
    static let shared = XunleiSession()
    private let store: FishCredentialStore
    private let service: XunleiAuthService

    init(store: FishCredentialStore = FishSecureStore.shared, service: XunleiAuthService = XunleiAuthService()) {
        self.store = store
        self.service = service
    }

    func storedCredential() throws -> XunleiCredential? {
        guard let data = try store.data(for: "xunlei") else { return nil }
        return try XunleiCredential(responseData: data)
    }

    func finishLogin(_ credential: XunleiCredential) async throws -> XunleiCredential {
        // Android persists token before /user/me. Preserve usable authorization if profile is unavailable.
        try store.set(credential.raw, for: "xunlei")
        do {
            let profiled = try await service.userInfo(credential: credential)
            try store.set(profiled.raw, for: "xunlei")
            return profiled
        } catch {
            return credential
        }
    }

    func validatedCredential() async throws -> XunleiCredential {
        guard let stored = try storedCredential() else { throw XunleiAuthError.notLoggedIn }
        if !stored.accessToken.isEmpty {
            do {
                let profiled = try await service.userInfo(credential: stored)
                try store.set(profiled.raw, for: "xunlei")
                return profiled
            } catch {
                // Android j() falls through to refresh after a failed profile check.
            }
        }
        // 迅雷无独立 refresh 端点（Go 参考）；用 userInfo 校验后返回已存凭据
        do {
            let profiled = try await service.userInfo(credential: stored)
            try store.set(profiled.raw, for: "xunlei")
            return profiled
        } catch {
            return stored
        }
    }

    func authorizationHeader() async throws -> String {
        (try await validatedCredential()).authorizationHeader
    }

    func logout() throws {
        try store.remove("xunlei")
    }
}
