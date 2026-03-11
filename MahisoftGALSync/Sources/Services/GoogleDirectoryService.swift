import Foundation
import os

actor GoogleDirectoryService {
    static let shared = GoogleDirectoryService()

    private init() {}

    /// Fetches directory people for an account using the People API (directory.readonly scope).
    func fetchDirectory(for account: SyncAccount) async throws -> [DirectoryPerson] {
        let accessToken = try await GoogleAuthService.shared.validAccessToken(for: account.email)
        return try await fetchPeopleDirectory(domain: account.domain, accessToken: accessToken)
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
