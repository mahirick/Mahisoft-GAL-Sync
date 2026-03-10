import Foundation

struct SyncState: Codable {
    var lastSyncTimestamps: [String: Date] // keyed by account email
    var directoryHashes: [String: String]  // keyed by account email, hash of directory contents

    init() {
        self.lastSyncTimestamps = [:]
        self.directoryHashes = [:]
    }

    static var storageURL: URL {
        Constants.appSupportDirectory.appendingPathComponent("sync_state.json")
    }

    static func load() -> SyncState {
        guard let data = try? Data(contentsOf: storageURL) else { return SyncState() }
        return (try? JSONDecoder().decode(SyncState.self, from: data)) ?? SyncState()
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: Self.storageURL, options: .atomic)
    }

    mutating func recordSync(for email: String, hash: String) {
        lastSyncTimestamps[email] = Date()
        directoryHashes[email] = hash
    }

    func hasChanged(for email: String, newHash: String) -> Bool {
        directoryHashes[email] != newHash
    }
}
