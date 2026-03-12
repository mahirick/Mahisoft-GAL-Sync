import SwiftUI
import Contacts

struct MenuBarView: View {
    @Environment(SyncOrchestrator.self) private var orchestrator
    @Environment(LogStore.self) private var logStore
    @Environment(UpdateChecker.self) private var updateChecker
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            // App name header with version
            Text("\(Constants.appName) v\(appVersion)")
                .font(.headline)

            Divider()

            // Update status
            updateStatusView
            Divider()

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
                Task { await updateChecker.checkAndAlert() }
            }
            .disabled({
                if case .checking = updateChecker.checkState { return true }
                return false
            }())

            if !contactsAuthorized {
                Divider()
                Button("Grant Contacts Access...") {
                    openContactsSettings()
                }
            }

            Divider()

            Button("Quit \(Constants.appName)") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    // MARK: - Update Status

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateChecker.checkState {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking for updates...")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        case .upToDate:
            Text("You're up to date")
                .foregroundStyle(.secondary)
                .font(.caption)
        case .updateAvailable(let version, let notes):
            VStack(alignment: .leading, spacing: 2) {
                Button("Update to v\(version)...") {
                    updateChecker.openDownloadPage()
                }
                if let notes {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        case .failed:
            Text("Update check failed")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
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

        Button("Show GAL in Contacts") {
            NSWorkspace.shared.open(URL(string: "addressbook://")!)
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
