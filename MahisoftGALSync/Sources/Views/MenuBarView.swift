import SwiftUI
import Contacts

struct MenuBarView: View {
    @Environment(SyncOrchestrator.self) private var orchestrator
    @Environment(LogStore.self) private var logStore
    @Environment(\.openWindow) private var openWindow
    private var updateChecker = UpdateChecker.shared

    var body: some View {
        Group {
            // App name header with version
            Text("Mahisoft GAL Sync v\(appVersion)")
                .font(.headline)

            Divider()

            // Update notification
            if let version = updateChecker.availableVersion {
                Button("Update Available: v\(version)") {
                    updateChecker.openDownloadPage()
                }

                Divider()
            }

            if orchestrator.accounts.isEmpty {
                getStartedSection
            } else {
                syncSection
            }

            Divider()

            Button("Preferences...") {
                openWindow(id: "preferences")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Activity Log\(logStore.recentErrors.isEmpty ? "" : " (\(logStore.recentErrors.count))")") {
                openWindow(id: "log")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("How It Works") {
                openWindow(id: "preferences")
                NSApp.activate(ignoringOtherApps: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NotificationCenter.default.post(name: .showHowItWorks, object: nil)
                }
            }

            Button("Check for Updates...") {
                Task { await updateChecker.check() }
            }

            if !contactsAuthorized {
                Divider()
                Button("Grant Contacts Access...") {
                    openContactsSettings()
                }
            }

            Divider()

            Button("Quit Mahisoft GAL Sync") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    // MARK: - Contacts Permission

    private var contactsAuthorized: Bool {
        CNContactStore.authorizationStatus(for: .contacts) == .authorized
    }

    private func openContactsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
            NSWorkspace.shared.open(url)
        }
        logStore.info("User directed to Contacts privacy settings", category: "contacts")
    }

    // MARK: - Get Started

    @ViewBuilder
    private var getStartedSection: some View {
        Text("No accounts configured")
            .foregroundStyle(.secondary)

        Button("Add Account...") {
            openWindow(id: "preferences")
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Sync Status

    @ViewBuilder
    private var syncSection: some View {
        if orchestrator.isSyncing {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Syncing...")
            }
        } else {
            Button("Sync Now") {
                Task {
                    await orchestrator.syncAllAccounts()
                }
            }
        }

        if let lastSync = orchestrator.lastSyncDate {
            Text("Last synced: \(lastSync.formatted(.relative(presentation: .named)))")
                .foregroundStyle(.secondary)
                .font(.caption)
        }

        if let summary = orchestrator.lastSyncSummary {
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if let error = orchestrator.syncError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }

        if orchestrator.hasAccountsNeedingReauth {
            Text("Account needs re-authentication")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}
