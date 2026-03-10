import AppKit
import Contacts
import os

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ensureSingleInstance() else { return }
        Logger.app.info("MahisoftGALSync launched")

        Task { @MainActor in
            let log = LogStore.shared
            log.info("Application launched", category: "app")

            // Prompt for contacts access if not yet granted
            await Self.promptForContactsAccessIfNeeded()

            // Start scheduled sync
            let intervalHours = UserDefaults.standard.object(forKey: "syncIntervalHours") as? Int
                ?? Constants.Defaults.syncIntervalHours
            SyncOrchestrator.shared.startScheduledSync(intervalHours: intervalHours)

            // Sync on launch if enabled
            let syncOnLaunch = UserDefaults.standard.object(forKey: "syncOnLaunch") as? Bool
                ?? Constants.Defaults.syncOnLaunch

            if syncOnLaunch && !SyncOrchestrator.shared.accounts.isEmpty {
                await SyncOrchestrator.shared.syncAllAccounts()
            }

            // Check for updates
            await UpdateChecker.shared.checkIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            SyncOrchestrator.shared.stopScheduledSync()
            LogStore.shared.info("Application terminating", category: "app")
        }
    }

    // MARK: - Single Instance

    /// Returns `true` if this is the only running instance; terminates and returns `false` otherwise.
    private func ensureSingleInstance() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.mahisoft.MahisoftGALSync"
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        let others = running.filter { $0 != NSRunningApplication.current }

        guard others.isEmpty else {
            Logger.app.warning("Another instance of MahisoftGALSync is already running — terminating this one.")
            // Activate the existing instance so the user sees it
            others.first?.activate()
            // Terminate after a brief delay so the app delegate can finish setup cleanly
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
            return false
        }
        return true
    }

    // MARK: - Contacts Permission

    @MainActor
    static func promptForContactsAccessIfNeeded() async {
        let log = LogStore.shared
        let status = CNContactStore.authorizationStatus(for: .contacts)

        switch status {
        case .authorized:
            log.info("Contacts access already granted", category: "contacts")
        case .notDetermined:
            do {
                let granted = try await ContactsSyncService.shared.requestAccess()
                if granted {
                    log.info("Contacts access granted", category: "contacts")
                } else {
                    log.warning("Contacts access denied by user", category: "contacts")
                }
            } catch {
                log.log(error, context: "Requesting contacts access", category: "contacts")
            }
        case .denied, .restricted:
            log.warning("Contacts access denied/restricted. User needs to enable in System Settings.", category: "contacts")
        @unknown default:
            log.warning("Unknown contacts authorization status: \(String(describing: status))", category: "contacts")
        }
    }
}
