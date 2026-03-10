import Foundation
import os

actor GoogleDirectoryService {
    static let shared = GoogleDirectoryService()

    private init() {}

    /// Fetches directory people for an account. Tries admin API first if marked admin,
    /// otherwise uses People API. Returns the list and whether admin access was used.
    func fetchDirectory(for account: SyncAccount, includeSuspended: Bool) async throws -> (people: [DirectoryPerson], isAdmin: Bool) {
        let accessToken = try await GoogleAuthService.shared.validAccessToken(for: account.email)

        if account.isAdmin {
            do {
                let people = try await fetchAdminDirectory(
                    domain: account.domain,
                    accessToken: accessToken,
                    includeSuspended: includeSuspended
                )
                return (people, true)
            } catch MahisoftGALSyncError.apiError(let code, let message) where code == 403 {
                Logger.sync.info("Admin API returned 403 for \(account.email), falling back to People API. Response: \(message)")
            }
        }

        let people = try await fetchPeopleDirectory(domain: account.domain, accessToken: accessToken)
        return (people, false)
    }

    /// Determines if an account has admin access by probing the Admin Directory API.
    func checkAdminAccess(for email: String, domain: String) async throws -> Bool {
        let accessToken = try await GoogleAuthService.shared.validAccessToken(for: email)

        guard var components = URLComponents(string: Constants.GoogleAPI.adminDirectoryUsersURL) else {
            Logger.sync.error("Invalid Admin Directory API URL")
            return false
        }

        components.queryItems = [
            URLQueryItem(name: "domain", value: domain),
            URLQueryItem(name: "maxResults", value: "1"),
        ]

        guard let url = components.url else {
            Logger.sync.error("Failed to construct admin check URL for \(domain)")
            return false
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            let isAdmin = httpResponse.statusCode == 200
            Logger.sync.info("Admin check for \(email): HTTP \(httpResponse.statusCode) → \(isAdmin ? "admin" : "non-admin")")
            return isAdmin
        } catch {
            Logger.sync.error("Admin check request failed for \(email): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Admin Directory API

    private func fetchAdminDirectory(domain: String, accessToken: String, includeSuspended: Bool) async throws -> [DirectoryPerson] {
        var allPeople: [DirectoryPerson] = []
        var pageToken: String?
        var pageCount = 0

        repeat {
            guard var components = URLComponents(string: Constants.GoogleAPI.adminDirectoryUsersURL) else {
                throw MahisoftGALSyncError.oauthFlowFailed("Invalid Admin Directory API URL")
            }

            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "domain", value: domain),
                URLQueryItem(name: "maxResults", value: "500"),
                URLQueryItem(name: "projection", value: "full"),
                URLQueryItem(name: "orderBy", value: "familyName"),
            ]

            if let token = pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: token))
            }
            components.queryItems = queryItems

            guard let url = components.url else {
                throw MahisoftGALSyncError.invalidResponse
            }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await performRequest(request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw MahisoftGALSyncError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? "unknown"
                throw MahisoftGALSyncError.apiError(statusCode: httpResponse.statusCode, message: body)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                Logger.sync.error("Admin directory: failed to parse response JSON for page \(pageCount)")
                throw MahisoftGALSyncError.invalidResponse
            }

            if let users = json["users"] as? [[String: Any]] {
                for userJSON in users {
                    if let person = DirectoryPerson(fromAdminJSON: userJSON, domain: domain) {
                        if includeSuspended || !person.isSuspended {
                            allPeople.append(person)
                        }
                    }
                }
            }

            pageToken = json["nextPageToken"] as? String
            pageCount += 1
            Logger.sync.debug("Admin API page \(pageCount): \(allPeople.count) people total")
        } while pageToken != nil

        Logger.sync.info("Fetched \(allPeople.count) people from admin directory for \(domain) (\(pageCount) page(s))")
        return allPeople
    }

    // MARK: - People API (Directory)

    private func fetchPeopleDirectory(domain: String, accessToken: String) async throws -> [DirectoryPerson] {
        var allPeople: [DirectoryPerson] = []
        var pageToken: String?
        var pageCount = 0

        repeat {
            guard var components = URLComponents(string: Constants.GoogleAPI.peopleDirectoryURL) else {
                throw MahisoftGALSyncError.oauthFlowFailed("Invalid People API URL")
            }

            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "readMask", value: "names,emailAddresses,phoneNumbers,photos,organizations"),
                URLQueryItem(name: "sources", value: "DIRECTORY_SOURCE_TYPE_DOMAIN_PROFILE"),
                URLQueryItem(name: "pageSize", value: "1000"),
            ]

            if let token = pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: token))
            }
            components.queryItems = queryItems

            guard let url = components.url else {
                throw MahisoftGALSyncError.invalidResponse
            }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await performRequest(request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw MahisoftGALSyncError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? "unknown"
                throw MahisoftGALSyncError.apiError(statusCode: httpResponse.statusCode, message: body)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                Logger.sync.error("People API: failed to parse response JSON for page \(pageCount)")
                throw MahisoftGALSyncError.invalidResponse
            }

            if let people = json["people"] as? [[String: Any]] {
                for personJSON in people {
                    if let person = DirectoryPerson(fromPeopleJSON: personJSON, domain: domain) {
                        allPeople.append(person)
                    }
                }
            }

            pageToken = json["nextPageToken"] as? String
            pageCount += 1
            Logger.sync.debug("People API page \(pageCount): \(allPeople.count) people total")
        } while pageToken != nil

        Logger.sync.info("Fetched \(allPeople.count) people from People API for \(domain) (\(pageCount) page(s))")
        return allPeople
    }

    // MARK: - Network with Exponential Backoff

    private func performRequest(_ request: URLRequest, maxRetries: Int = 3) async throws -> (Data, URLResponse) {
        var lastError: Error?
        var delay: TimeInterval = 1

        for attempt in 1...maxRetries {
            do {
                return try await URLSession.shared.data(for: request)
            } catch {
                lastError = error
                Logger.sync.warning("Request to \(request.url?.host ?? "unknown") failed (attempt \(attempt)/\(maxRetries)): \(error.localizedDescription)")

                if attempt < maxRetries {
                    try await Task.sleep(for: .seconds(delay))
                    delay *= 2
                }
            }
        }

        throw MahisoftGALSyncError.networkError(lastError ?? URLError(.unknown))
    }
}
