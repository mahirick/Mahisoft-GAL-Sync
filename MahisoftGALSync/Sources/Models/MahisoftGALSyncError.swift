import Foundation

enum MahisoftGALSyncError: LocalizedError {
    case oauthConfigMissing
    case oauthFlowFailed(String)
    case tokenRefreshFailed
    case tokenNotFound
    case networkError(Error)
    case apiError(statusCode: Int, message: String)
    case contactsAccessDenied
    case contactsWriteFailed(Error)
    case accountNotFound
    case invalidResponse
    case pkceVerifierMissing

    var errorDescription: String? {
        switch self {
        case .oauthConfigMissing:
            return "OAuth configuration is missing. Please check GoogleOAuthConfig.plist."
        case .oauthFlowFailed(let reason):
            return "OAuth flow failed: \(reason)"
        case .tokenRefreshFailed:
            return "Failed to refresh access token. Please re-authenticate."
        case .tokenNotFound:
            return "No stored credentials found for this account."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .contactsAccessDenied:
            return "Contacts access denied. Please enable in System Settings → Privacy & Security → Contacts."
        case .contactsWriteFailed(let error):
            return "Failed to write contacts: \(error.localizedDescription)"
        case .accountNotFound:
            return "Account not found."
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .pkceVerifierMissing:
            return "PKCE code verifier was not generated. Please try again."
        }
    }
}
