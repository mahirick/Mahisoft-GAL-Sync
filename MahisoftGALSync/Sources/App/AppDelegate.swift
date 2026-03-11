import AppKit
import Contacts
import os
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ensureSingleInstance() else { return }
        Logger.app.info("MahisoftGALSync launched")

        Task { @MainActor in
            let log = LogStore.shared
            log.info("Application launched", category: "app")

            // On first launch: explain Keychain access before anything touches it
            showKeychainExplanationIfNeeded()

            // On first launch: ask user to name their contact group
            promptForGroupNameIfNeeded()

            // On first launch: register for launch at login (default ON per Constants)
            registerLaunchAtLoginIfFirstRun()

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
            others.first?.activate()
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
            return false
        }
        return true
    }

    // MARK: - First Launch

    /// Shows a one-time alert explaining why macOS will prompt for Keychain access.
    /// macOS shows "MahisoftGALSync wants to use the Login Keychain" when tokens are
    /// first stored — clicking "Always Allow" prevents repeated prompts.
    /// The explanation is shown once per build — each new build resets macOS Keychain
    /// permissions (new code signature), so the user needs the reminder again.
    @MainActor
    private func showKeychainExplanationIfNeeded() {
        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let key = "keychainExplanationShownForBuild"
        guard UserDefaults.standard.string(forKey: key) != currentBuild else { return }
        UserDefaults.standard.set(currentBuild, forKey: key)

        let alert = NSAlert()
        alert.messageText = "Keychain Access"
        alert.informativeText = """
            Mahisoft GAL Sync stores your Google sign-in credentials securely in the macOS Keychain.

            When prompted by macOS, click "Always Allow" so you aren't asked again each time the app syncs.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Got It")
        alert.runModal()
    }

    /// Asks the user to name their contact group on the very first launch.
    /// Only shown once — skipped on all subsequent launches.
    @MainActor
    private func promptForGroupNameIfNeeded() {
        guard UserDefaults.standard.object(forKey: "contactGroupName") == nil else { return }

        let alert = NSAlert()
        alert.messageText = "Name Your Contact Group"
        alert.informativeText = "What would you like to call the group in Apple Contacts where your company directory will be synced?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        input.stringValue = Constants.Defaults.contactGroupName
        input.placeholderString = Constants.Defaults.contactGroupName
        input.bezelStyle = .roundedBezel
        alert.accessoryView = input

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()

        let name = input.stringValue.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(name.isEmpty ? Constants.Defaults.contactGroupName : name, forKey: "contactGroupName")
        Logger.app.info("Contact group name set to: \(name)")
    }

    /// Registers the app for launch at login on the very first run.
    /// Respects the user's preference if they've already changed it.
    @MainActor
    private func registerLaunchAtLoginIfFirstRun() {
        let key = "hasRegisteredLaunchAtLogin"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let shouldLaunch = UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool
            ?? Constants.Defaults.launchAtLogin

        guard shouldLaunch else { return }

        do {
            try SMAppService.mainApp.register()
            Logger.app.info("Registered for launch at login on first run")
        } catch {
            Logger.app.warning("Could not register for launch at login: \(error.localizedDescription)")
        }
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
