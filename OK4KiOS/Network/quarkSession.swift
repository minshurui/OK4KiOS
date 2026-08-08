import Foundation

actor QuarkSession {
    static let shared = QuarkSession()
    private let store: FishCredentialStore
    private let service: QuarkAuthService

    init(store: FishCredentialStore = FishSecureStore.shared, service: QuarkAuthService = QuarkAuthService()) {
        self.store = store
        self.service = service
    }

    func storedCredential() throws -> QuarkCredential? {
        guard let data = try store.data(for: "quark") else { return nil }
        return try QuarkCredential(responseData: data)
    }

    func finishLogin(_ credential: QuarkCredential) async throws -> QuarkCredential {
        // Android persists token before /user/me. Preserve usable authorization if profile is unavailable.
        try store.set(credential.raw, for: "quark")
        do {
            let profiled = try await service.profile(for: credential)
            try store.set(profiled.raw, for: "quark")
            return profiled
        } catch {
            return credential
        }
    }

    func validatedCredential() async throws -> QuarkCredential {
        guard let stored = try storedCredential() else { throw QuarkAuthError.notLoggedIn }
        if !stored.accessToken.isEmpty {
            do {
                let profiled = try await service.profile(for: stored)
                try store.set(profiled.raw, for: "quark")
                return profiled
            } catch {
                // Android falls through to refresh after a failed profile check.
            }
        }
        let refreshed = try await service.refresh(stored)
        try store.set(refreshed.raw, for: "quark")
        do {
            let profiled = try await service.profile(for: refreshed)
            try store.set(profiled.raw, for: "quark")
            return profiled
        } catch {
            return refreshed
        }
    }

    func authorizationHeader() async throws -> String {
        (try await validatedCredential()).authorizationHeader
    }

    func logout() throws {
        try store.remove("quark")
    }
}
