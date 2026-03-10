import Foundation
import KeychainAccess
import os

actor KeychainService {
    static let shared = KeychainService()

    private let keychain: Keychain

    private init() {
        // Binding all items to the shared access group means macOS asks for
        // permission once (the "Always Allow" dialog) and applies it to every
        // item the app ever reads or writes — no per-item repeat prompts.
        self.keychain = Keychain(service: Constants.keychainService,
                                 accessGroup: Constants.keychainAccessGroup)
            .accessibility(.afterFirstUnlock)
    }

    // MARK: - Token Storage

    struct OAuthTokens: Codable, Sendable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var scope: String
    }

    func storeTokens(_ tokens: OAuthTokens, for email: String) throws {
        do {
            let data = try JSONEncoder().encode(tokens)
            try keychain.set(data, key: tokenKey(for: email))
            Logger.auth.debug("Stored tokens for \(email)")
        } catch {
            Logger.auth.error("Failed to store tokens for \(email): \(error.localizedDescription)")
            throw error
        }
    }

    func loadTokens(for email: String) throws -> OAuthTokens? {
        do {
            guard let data = try keychain.getData(tokenKey(for: email)) else {
                Logger.auth.debug("No tokens found for \(email)")
                return nil
            }
            return try JSONDecoder().decode(OAuthTokens.self, from: data)
        } catch {
            Logger.auth.error("Failed to load tokens for \(email): \(error.localizedDescription)")
            throw error
        }
    }

    func removeTokens(for email: String) throws {
        do {
            try keychain.remove(tokenKey(for: email))
            Logger.auth.debug("Removed tokens for \(email)")
        } catch {
            Logger.auth.error("Failed to remove tokens for \(email): \(error.localizedDescription)")
            throw error
        }
    }

    func isTokenExpired(for email: String) throws -> Bool {
        guard let tokens = try loadTokens(for: email) else { return true }
        return tokens.expiresAt < Date()
    }

    // MARK: - Private

    private func tokenKey(for email: String) -> String {
        "oauth_tokens_\(email)"
    }
}

