import AppKit
import CryptoKit
import Foundation
import os

actor GoogleAuthService {
    static let shared = GoogleAuthService()

    private var pendingPKCEVerifier: String?
    private var pendingState: String?
    private var callbackServer: OAuthCallbackServer?

    private init() {}

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateState() -> String {
        UUID().uuidString
    }

    // MARK: - OAuth Flow

    /// Performs the full OAuth flow: starts a loopback server, opens the browser,
    /// waits for the callback, exchanges the code for tokens, and returns the result.
    func performOAuthFlow(useAdminScope: Bool = false) async throws -> (tokens: KeychainService.OAuthTokens, email: String) {
        let clientID = try Constants.OAuth.resolveClientID()
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        let state = generateState()

        self.pendingPKCEVerifier = verifier
        self.pendingState = state

        // Start loopback server FIRST — this binds the port synchronously
        let server = try OAuthCallbackServer()
        self.callbackServer = server
        let redirectURI = server.redirectURI

        let scope = useAdminScope
            ? Constants.OAuth.scopeAdminDirectoryUserReadonly
            : Constants.OAuth.scopeDirectoryReadonly

        guard var components = URLComponents(string: Constants.OAuth.authURI) else {
            server.stop()
            throw MahisoftGALSyncError.oauthFlowFailed("Invalid authorization endpoint URL")
        }

        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "\(scope) email profile"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        guard let authURL = components.url else {
            server.stop()
            throw MahisoftGALSyncError.oauthFlowFailed("Failed to construct authorization URL")
        }

        Logger.auth.info("Opening browser for OAuth (loopback on \(redirectURI))")

        // Open browser — must be done on main actor
        await MainActor.run {
            NSWorkspace.shared.open(authURL)
        }

        // Wait for Google to redirect back to our loopback server
        let url: URL
        do {
            url = try await server.awaitCallback()
        } catch {
            server.stop()
            throw error
        }
        server.stop()
        self.callbackServer = nil

        // Process the callback
        return try await handleCallback(url: url, expectedRedirectURI: redirectURI)
    }

    private func handleCallback(url: URL, expectedRedirectURI: String) async throws -> (tokens: KeychainService.OAuthTokens, email: String) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            throw MahisoftGALSyncError.oauthFlowFailed("Invalid callback URL")
        }

        // Check for errors from Google
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            let description = queryItems.first(where: { $0.name == "error_description" })?.value ?? error
            throw MahisoftGALSyncError.oauthFlowFailed(description)
        }

        // Validate state to prevent CSRF
        guard let returnedState = queryItems.first(where: { $0.name == "state" })?.value,
              returnedState == pendingState else {
            throw MahisoftGALSyncError.oauthFlowFailed("State mismatch — possible CSRF attack")
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            throw MahisoftGALSyncError.oauthFlowFailed("No authorization code in callback")
        }

        guard let verifier = pendingPKCEVerifier else {
            throw MahisoftGALSyncError.pkceVerifierMissing
        }

        // Exchange code for tokens using PKCE (no client_secret needed)
        let tokens = try await exchangeCodeForTokens(code: code, codeVerifier: verifier, redirectURI: expectedRedirectURI)

        // Clear pending state
        self.pendingPKCEVerifier = nil
        self.pendingState = nil

        // Get user email from userinfo
        let email = try await fetchUserEmail(accessToken: tokens.accessToken)

        Logger.auth.info("OAuth flow completed successfully for \(email)")
        return (tokens, email)
    }

    // MARK: - Token Exchange

    private func exchangeCodeForTokens(code: String, codeVerifier: String, redirectURI: String) async throws -> KeychainService.OAuthTokens {
        guard let tokenURL = URL(string: Constants.OAuth.tokenURI) else {
            throw MahisoftGALSyncError.oauthFlowFailed("Invalid token endpoint URL")
        }

        let clientID = try Constants.OAuth.resolveClientID()
        let clientSecret = try Constants.OAuth.resolveClientSecret()

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [String: String] = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": code,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ]

        request.httpBody = params
            .map { key, value in
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(key)=\(encodedValue)"
            }
            .joined(separator: "&")
            .data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            Logger.auth.error("Token exchange network error: \(error.localizedDescription)")
            throw MahisoftGALSyncError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MahisoftGALSyncError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            Logger.auth.error("Token exchange failed: HTTP \(httpResponse.statusCode) — \(body)")
            throw MahisoftGALSyncError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        let json: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw MahisoftGALSyncError.invalidResponse
            }
            json = parsed
        } catch {
            Logger.auth.error("Token exchange: failed to parse response JSON")
            throw MahisoftGALSyncError.invalidResponse
        }

        guard let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            Logger.auth.error("Token exchange: response missing required fields (access_token, refresh_token, expires_in)")
            throw MahisoftGALSyncError.invalidResponse
        }

        let scope = json["scope"] as? String ?? ""

        return KeychainService.OAuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            scope: scope
        )
    }

    // MARK: - Token Refresh

    func refreshAccessToken(for email: String) async throws -> String {
        guard let tokens = try await KeychainService.shared.loadTokens(for: email) else {
            throw MahisoftGALSyncError.tokenNotFound
        }

        guard let tokenURL = URL(string: Constants.OAuth.tokenURI) else {
            throw MahisoftGALSyncError.oauthFlowFailed("Invalid token endpoint URL")
        }

        let clientID = try Constants.OAuth.resolveClientID()
        let clientSecret = try Constants.OAuth.resolveClientSecret()

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [String: String] = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "refresh_token": tokens.refreshToken,
            "grant_type": "refresh_token",
        ]

        request.httpBody = params
            .map { key, value in
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(key)=\(encodedValue)"
            }
            .joined(separator: "&")
            .data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            Logger.auth.error("Token refresh network error for \(email): \(error.localizedDescription)")
            throw MahisoftGALSyncError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            Logger.auth.error("Token refresh failed for \(email): \(body)")
            throw MahisoftGALSyncError.tokenRefreshFailed
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            Logger.auth.error("Token refresh: invalid response body for \(email)")
            throw MahisoftGALSyncError.tokenRefreshFailed
        }

        var updatedTokens = tokens
        updatedTokens.accessToken = accessToken
        updatedTokens.expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        try await KeychainService.shared.storeTokens(updatedTokens, for: email)

        Logger.auth.info("Token refreshed for \(email)")
        return accessToken
    }

    /// Returns a valid access token, refreshing automatically if expired or about to expire.
    func validAccessToken(for email: String) async throws -> String {
        guard let tokens = try await KeychainService.shared.loadTokens(for: email) else {
            throw MahisoftGALSyncError.tokenNotFound
        }

        // Refresh if token expires within 60 seconds
        if tokens.expiresAt > Date().addingTimeInterval(60) {
            return tokens.accessToken
        }

        return try await refreshAccessToken(for: email)
    }

    // MARK: - User Info

    private func fetchUserEmail(accessToken: String) async throws -> String {
        guard let url = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo") else {
            throw MahisoftGALSyncError.oauthFlowFailed("Invalid userinfo endpoint URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            Logger.auth.error("Userinfo request failed: \(error.localizedDescription)")
            throw MahisoftGALSyncError.networkError(error)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String else {
            Logger.auth.error("Userinfo response missing email field")
            throw MahisoftGALSyncError.invalidResponse
        }

        return email
    }
}
