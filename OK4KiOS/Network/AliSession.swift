import Foundation

actor AliSession {
    static let shared = AliSession()
    private let store: FishCredentialStore
    private let service: AliAuthService

    init(store: FishCredentialStore = FishSecureStore.shared, service: AliAuthService = AliAuthService()) {
        self.store = store
        self.service = service
    }

    func storedCredential() throws -> AliCredential? {
        guard let data = try store.data(for: "ali") else { return nil }
        return try AliCredential(responseData: data)
    }

    func finishLogin(_ credential: AliCredential) async throws -> AliCredential {
        // Android persists token before profile. Preserve usable authorization if profile is unavailable.
        try store.set(credential.raw, for: "ali")
        do {
            let profiled = try await service.profile(for: credential)
            try store.set(profiled.raw, for: "ali")
            return profiled
        } catch {
            return credential
        }
    }

    func validatedCredential() async throws -> AliCredential {
        guard let stored = try storedCredential() else { throw AliAuthError.notLoggedIn }
        if !stored.accessToken.isEmpty {
            do {
                let profiled = try await service.profile(for: stored)
                try store.set(profiled.raw, for: "ali")
                return profiled
            } catch {
                // Android falls through to refresh after a failed profile check.
            }
        }
        let refreshed = try await service.refresh(stored)
        try store.set(refreshed.raw, for: "ali")
        do {
            let profiled = try await service.profile(for: refreshed)
            try store.set(profiled.raw, for: "ali")
            return profiled
        } catch {
            return refreshed
        }
    }

    func authorizationHeader() async throws -> String {
        (try await validatedCredential()).authorizationHeader
    }

    func logout() throws {
        try store.remove("ali")
    }
}
