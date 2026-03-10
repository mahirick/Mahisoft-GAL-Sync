import Foundation
import os

enum Constants {
    static let bundleIdentifier = "com.mahisoft.MahisoftGALSync"
    static let appName = "Mahisoft GAL Sync"
    static let keychainService = "com.mahisoft.MahisoftGALSync.oauth"

    enum OAuth {
        static let authURI = "https://accounts.google.com/o/oauth2/v2/auth"
        static let tokenURI = "https://oauth2.googleapis.com/token"
        static let redirectURI = "com.mahisoft.mahisoftgalsync:/oauth/callback"
        static let scopeDirectoryReadonly = "https://www.googleapis.com/auth/directory.readonly"
        static let scopeAdminDirectoryUserReadonly = "https://www.googleapis.com/auth/admin.directory.user.readonly"

        /// Resolves the OAuth client ID from Secrets.plist (gitignored).
        /// Falls back to GoogleOAuthConfig.plist for backwards compatibility.
        static func resolveClientID() throws -> String {
            // Primary: Secrets.plist (gitignored)
            if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
               let dict = NSDictionary(contentsOfFile: path),
               let clientID = dict["GOOGLE_CLIENT_ID"] as? String,
               !clientID.isEmpty,
               !clientID.contains("PUT_YOUR") {
                return clientID
            }

            // Fallback: GoogleOAuthConfig.plist
            if let path = Bundle.main.path(forResource: "GoogleOAuthConfig", ofType: "plist"),
               let dict = NSDictionary(contentsOfFile: path),
               let clientID = dict["CLIENT_ID"] as? String,
               !clientID.isEmpty,
               !clientID.contains("YOUR_CLIENT_ID") {
                return clientID
            }

            throw MahisoftGALSyncError.oauthConfigMissing
        }

        /// Resolves the OAuth client secret from Secrets.plist.
        /// Google Desktop OAuth clients require client_secret for token exchange.
        static func resolveClientSecret() throws -> String {
            if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
               let dict = NSDictionary(contentsOfFile: path),
               let secret = dict["GOOGLE_CLIENT_SECRET"] as? String,
               !secret.isEmpty,
               !secret.contains("PUT_YOUR") {
                return secret
            }

            throw MahisoftGALSyncError.oauthConfigMissing
        }
    }

    enum GoogleAPI {
        static let adminDirectoryUsersURL = "https://admin.googleapis.com/admin/directory/v1/users"
        static let peopleDirectoryURL = "https://people.googleapis.com/v1/people:listDirectoryPeople"
    }

    enum Defaults {
        static let syncIntervalHours = 4
        static let contactGroupName = "Company GAL"
        static let removeDeletedContacts = true
        static let syncOnLaunch = true
        static let includeSuspendedUsers = false
        static let includeProfilePhotos = true
        static let launchAtLogin = true
        static let separateGroupPerDomain = true
    }

    static let appSupportDirectory: URL = {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            Logger.app.error("Could not locate Application Support directory")
            return fm.temporaryDirectory.appendingPathComponent(bundleIdentifier)
        }
        let url = appSupport.appendingPathComponent(bundleIdentifier)
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            Logger.app.error("Failed to create app support directory: \(error.localizedDescription)")
        }
        return url
    }()
}
