import Foundation

struct SyncAccount: Identifiable, Codable, Equatable {
    let id: UUID
    var email: String
    var domain: String
    var isAdmin: Bool
    var lastSyncDate: Date?
    var lastSyncStatus: SyncStatus
    var needsReauth: Bool

    enum SyncStatus: String, Codable {
        case never
        case success
        case failed
        case inProgress
    }

    init(email: String) {
        self.id = UUID()
        self.email = email
        self.domain = email.components(separatedBy: "@").last ?? ""
        self.isAdmin = false
        self.lastSyncDate = nil
        self.lastSyncStatus = .never
        self.needsReauth = false
    }
}

// MARK: - Persistence

extension SyncAccount {
    static var storageURL: URL {
        Constants.appSupportDirectory.appendingPathComponent("accounts.json")
    }

    static func loadAll() -> [SyncAccount] {
        guard let data = try? Data(contentsOf: storageURL) else { return [] }
        return (try? JSONDecoder().decode([SyncAccount].self, from: data)) ?? []
    }

    static func saveAll(_ accounts: [SyncAccount]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(accounts) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
