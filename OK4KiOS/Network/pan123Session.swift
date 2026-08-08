import Foundation

actor Pan123Session {
    static let shared = Pan123Session()
    private let store: FishCredentialStore
    private let service: Pan123AuthService

    init(store: FishCredentialStore = FishSecureStore.shared, service: Pan123AuthService = Pan123AuthService()) {
        self.store = store
        self.service = service
    }

    func storedCredential() throws -> Pan123Credential? {
        guard let data = try store.data(for: "pan123") else { return nil }
        return try Pan123Credential(responseData: data)
    }

    func finishLogin(_ credential: Pan123Credential) async throws -> Pan123Credential {
        // Android persists token before /api/user/info. Preserve usable authorization if profile is unavailable.
        try store.set(credential.raw, for: "pan123")
        do {
            let profiled = try await service.profile(for: credential)
            try store.set(profiled.raw, for: "pan123")
            return profiled
        } catch {
            return credential
        }
    }

    func validatedCredential() async throws -> Pan123Credential {
        guard let stored = try storedCredential() else { throw Pan123AuthError.notLoggedIn }
        if !stored.accessToken.isEmpty {
            do {
                let profiled = try await service.profile(for: stored)
                try store.set(profiled.raw, for: "pan123")
                return profiled
            } catch {
                // Android falls through to refresh after a failed profile check.
            }
        }
        let refreshed = try await service.refresh(stored)
        try store.set(refreshed.raw, for: "pan123")
        do {
            let profiled = try await service.profile(for: refreshed)
            try store.set(profiled.raw, for: "pan123")
            return profiled
        } catch {
            return refreshed
        }
    }

    func authorizationHeader() async throws -> String {
        (try await validatedCredential()).authorizationHeader
    }

    func logout() throws {
        try store.remove("pan123")
    }
}
