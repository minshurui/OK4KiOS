import Foundation

actor GuangyaSession {
    static let shared = GuangyaSession()
    private let store: FishCredentialStore
    private let service: GuangyaAuthService

    init(store: FishCredentialStore = FishSecureStore.shared, service: GuangyaAuthService = GuangyaAuthService()) {
        self.store = store
        self.service = service
    }

    func storedCredential() throws -> GuangyaCredential? {
        guard let data = try store.data(for: "guangya") else { return nil }
        return try GuangyaCredential(responseData: data)
    }

    func finishLogin(_ credential: GuangyaCredential) async throws -> GuangyaCredential {
        // Android persists token before /user/me. Preserve usable authorization if profile is unavailable.
        try store.set(credential.raw, for: "guangya")
        do {
            let profiled = try await service.profile(for: credential)
            try store.set(profiled.raw, for: "guangya")
            return profiled
        } catch {
            return credential
        }
    }

    func validatedCredential() async throws -> GuangyaCredential {
        guard let stored = try storedCredential() else { throw GuangyaAuthError.notLoggedIn }
        if !stored.accessToken.isEmpty {
            do {
                let profiled = try await service.profile(for: stored)
                try store.set(profiled.raw, for: "guangya")
                return profiled
            } catch {
                // Android j() falls through to refresh after a failed profile check.
            }
        }
        let refreshed = try await service.refresh(stored)
        try store.set(refreshed.raw, for: "guangya")
        do {
            let profiled = try await service.profile(for: refreshed)
            try store.set(profiled.raw, for: "guangya")
            return profiled
        } catch {
            return refreshed
        }
    }

    func authorizationHeader() async throws -> String {
        (try await validatedCredential()).authorizationHeader
    }

    func logout() throws {
        try store.remove("guangya")
    }
}
