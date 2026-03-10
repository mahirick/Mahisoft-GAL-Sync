import Foundation
import os
import CryptoKit

@Observable
@MainActor
final class SyncOrchestrator {
    static let shared = SyncOrchestrator()

    // Observable state
    private(set) var accounts: [SyncAccount] = []
    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date?
    private(set) var lastSyncSummary: String?
    private(set) var syncError: String?

    private var syncTimer: Timer?
    private var syncState = SyncState.load()

    private init() {
        accounts = SyncAccount.loadAll()
        lastSyncDate = syncState.lastSyncTimestamps.values.max()
    }

    // MARK: - Account Management

    func addAccount(email: String, tokens: KeychainService.OAuthTokens) async {
        let log = LogStore.shared

        // Prevent duplicates
        guard !accounts.contains(where: { $0.email == email }) else {
            log.warning("Account \(email) already exists, skipping add", category: "auth")
            return
        }

        var account = SyncAccount(email: email)

        do {
            try await KeychainService.shared.storeTokens(tokens, for: email)
        } catch {
            log.log(error, context: "Storing tokens for \(email)", category: "auth")
            return
        }

        // Check admin access
        do {
            account.isAdmin = try await GoogleDirectoryService.shared.checkAdminAccess(
                for: email, domain: account.domain
            )
            log.info("\(email) admin access: \(account.isAdmin)", category: "auth")
        } catch {
            log.log(error, context: "Checking admin access for \(email)", category: "auth")
            // Non-fatal — default to non-admin
        }

        accounts.append(account)
        saveAccounts()
    }

    func removeAccount(_ account: SyncAccount) async {
        let log = LogStore.shared

        accounts.removeAll { $0.id == account.id }
        saveAccounts()

        do {
            try await KeychainService.shared.removeTokens(for: account.email)
        } catch {
            log.log(error, context: "Removing tokens for \(account.email)", category: "auth")
        }

        syncState.lastSyncTimestamps.removeValue(forKey: account.email)
        syncState.directoryHashes.removeValue(forKey: account.email)
        syncState.save()

        log.info("Removed account: \(account.email)", category: "auth")
    }

    func markAccountNeedsReauth(_ email: String) {
        if let index = accounts.firstIndex(where: { $0.email == email }) {
            accounts[index].needsReauth = true
            saveAccounts()
            LogStore.shared.warning("Account \(email) needs re-authentication", category: "auth")
        }
    }

    // MARK: - Sync Scheduling

    func startScheduledSync(intervalHours: Int) {
        stopScheduledSync()
        let interval = TimeInterval(intervalHours * 3600)
        syncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.syncAllAccounts()
            }
        }
        Logger.sync.info("Scheduled sync every \(intervalHours) hours")
    }

    func stopScheduledSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    // MARK: - Sync Execution

    func syncAllAccounts() async {
        guard !isSyncing else {
            Logger.sync.info("Sync already in progress, skipping")
            return
        }

        let log = LogStore.shared
        isSyncing = true
        syncError = nil

        let includeSuspended = UserDefaults.standard.bool(forKey: "includeSuspendedUsers")
        let includePhotos = UserDefaults.standard.object(forKey: "includeProfilePhotos") as? Bool ?? Constants.Defaults.includeProfilePhotos
        let removeDeleted = UserDefaults.standard.object(forKey: "removeDeletedContacts") as? Bool ?? Constants.Defaults.removeDeletedContacts
        let separateGroups = UserDefaults.standard.bool(forKey: "separateGroupPerDomain")
        let baseGroupName = UserDefaults.standard.string(forKey: "contactGroupName") ?? Constants.Defaults.contactGroupName

        var totalAdded = 0
        var totalUpdated = 0
        var totalRemoved = 0
        var hadErrors = false

        log.info("Starting sync for \(accounts.count) account(s)", category: "sync")

        for i in accounts.indices {
            let account = accounts[i]
            guard !account.needsReauth else {
                log.warning("Skipping \(account.email) — needs re-authentication", category: "sync")
                continue
            }

            accounts[i].lastSyncStatus = .inProgress

            let groupName = separateGroups
                ? "\(account.domain.split(separator: ".").first?.capitalized ?? account.domain) Directory"
                : baseGroupName

            do {
                let (people, isAdmin) = try await GoogleDirectoryService.shared.fetchDirectory(
                    for: account,
                    includeSuspended: includeSuspended
                )

                if accounts[i].isAdmin != isAdmin {
                    accounts[i].isAdmin = isAdmin
                }

                log.info("Fetched \(people.count) people for \(account.email)", category: "sync")

                // Compute hash for change detection
                let hash = computeHash(for: people)
                let hasChanged = syncState.hasChanged(for: account.email, newHash: hash)

                if hasChanged {
                    let result = try await ContactsSyncService.shared.syncContacts(
                        people: people,
                        groupName: groupName,
                        removeDeleted: removeDeleted,
                        includePhotos: includePhotos
                    )

                    totalAdded += result.added
                    totalUpdated += result.updated
                    totalRemoved += result.removed

                    if result.photoErrors > 0 {
                        log.warning("\(result.photoErrors) photo download(s) failed for \(account.email)", category: "sync")
                    }

                    log.info("Synced \(account.email): \(result.summary)", category: "sync")
                } else {
                    log.info("No changes detected for \(account.email), skipping contact write", category: "sync")
                }

                syncState.recordSync(for: account.email, hash: hash)
                accounts[i].lastSyncDate = Date()
                accounts[i].lastSyncStatus = .success

            } catch let error as DirectorySyncError {
                accounts[i].lastSyncStatus = .failed
                hadErrors = true

                switch error {
                case .tokenRefreshFailed, .tokenNotFound:
                    accounts[i].needsReauth = true
                    log.error("Authentication expired for \(account.email). Please re-authenticate.", category: "auth")
                case .contactsAccessDenied:
                    log.error("Contacts access denied. Enable in System Settings → Privacy & Security → Contacts.", category: "contacts")
                default:
                    log.log(error, context: "Syncing \(account.email)", category: "sync")
                }
            } catch {
                accounts[i].lastSyncStatus = .failed
                hadErrors = true
                log.log(error, context: "Syncing \(account.email)", category: "sync")
            }
        }

        lastSyncDate = Date()
        lastSyncSummary = "\(totalAdded) added, \(totalUpdated) updated, \(totalRemoved) removed"
        syncError = hadErrors ? "Some accounts had errors — see Activity Log" : nil
        isSyncing = false

        saveAccounts()
        syncState.save()

        log.info("Sync complete: \(lastSyncSummary ?? "")", category: "sync")
    }

    // MARK: - Helpers

    private func saveAccounts() {
        SyncAccount.saveAll(accounts)
    }

    private func computeHash(for people: [DirectoryPerson]) -> String {
        let sorted = people.sorted { $0.primaryEmail < $1.primaryEmail }
        guard let data = try? JSONEncoder().encode(sorted) else {
            return UUID().uuidString
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    var hasAccountsNeedingReauth: Bool {
        accounts.contains { $0.needsReauth }
    }
}
