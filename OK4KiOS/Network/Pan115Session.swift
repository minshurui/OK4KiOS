import Foundation

actor Pan115Session {
    static let shared = Pan115Session()
    private let store: FishCredentialStore
    private let service: Pan115AuthService

    init(store: FishCredentialStore = FishSecureStore.shared, service: Pan115AuthService = Pan115AuthService()) {
        self.store = store
        self.service = service
    }

    func storedCredential() throws -> Pan115Credential? {
        guard let data = try store.data(for: "pan115") else { return nil }
        return try Pan115Credential(responseData: data)
    }

    func finishLogin(_ credential: Pan115Credential) async throws -> Pan115Credential {
        // Android persists token before profile. Preserve usable authorization if profile is unavailable.
        try store.set(credential.raw, for: "pan115")
        do {
            let profiled = try await service.profile(for: credential)
            try store.set(profiled.raw, for: "pan115")
            return profiled
        } catch {
            return credential
        }
    }

    func validatedCredential() async throws -> Pan115Credential {
        guard let stored = try storedCredential() else { throw Pan115AuthError.notLoggedIn }
        if !stored.token.isEmpty {
            do {
                let profiled = try await service.profile(for: stored)
                try store.set(profiled.raw, for: "pan115")
                return profiled
            } catch {
                // Android falls through to refresh after a failed profile check.
            }
        }
        // 115 无 refresh_token 机制，token 失效需重新扫码
        throw Pan115AuthError.notLoggedIn
    }

    func logout() throws {
        try store.remove("pan115")
    }
}
