import SwiftUI
import os

struct AccountsTab: View {
    @Environment(SyncOrchestrator.self) private var orchestrator
    @Environment(LogStore.self) private var logStore
    @State private var isAuthenticating = false
    @State private var authError: String?
    @State private var showRemoveConfirmation = false
    @State private var accountToRemove: SyncAccount?

    var body: some View {
        VStack(spacing: 0) {
            if orchestrator.accounts.isEmpty {
                emptyState
            } else {
                accountsList
            }

            Divider()

            // Bottom toolbar — Apple HIG pattern for list management
            HStack {
                Button {
                    addAccount()
                } label: {
                    Label("Add Account", systemImage: "plus")
                }
                .disabled(isAuthenticating)

                if isAuthenticating {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 4)
                }

                if !orchestrator.accounts.isEmpty {
                    Button {
                        Task { await orchestrator.syncAllAccounts() }
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(orchestrator.isSyncing)
                }

                Spacer()

                if orchestrator.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                }

                if let error = authError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            .padding(12)
        }
        .alert("Remove Account", isPresented: $showRemoveConfirmation, presenting: accountToRemove) { account in
            Button("Remove", role: .destructive) {
                Task {
                    await orchestrator.removeAccount(account)
                    logStore.info("User removed account: \(account.email)", category: "auth")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { account in
            Text("Remove \(account.email)?\n\nSynced contacts in the group will be kept, but future syncs will stop for this account.")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Accounts", systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text("Add a Google Workspace account to start syncing your company directory to Apple Contacts.")
        } actions: {
            Button("Add Account") {
                addAccount()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isAuthenticating)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Accounts List

    private var accountsList: some View {
        List {
            ForEach(orchestrator.accounts) { account in
                AccountRow(account: account) {
                    accountToRemove = account
                    showRemoveConfirmation = true
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Auth

    private func addAccount() {
        isAuthenticating = true
        authError = nil

        Task {
            do {
                logStore.info("Starting OAuth flow (loopback)...", category: "auth")
                let (tokens, email) = try await GoogleAuthService.shared.performOAuthFlow()
                logStore.info("OAuth completed for \(email)", category: "auth")

                await orchestrator.addAccount(email: email, tokens: tokens)
                logStore.info("Account added: \(email)", category: "auth")

                // Trigger initial sync for the new account
                await orchestrator.syncAllAccounts()
            } catch {
                authError = error.localizedDescription
                logStore.log(error, context: "OAuth flow", category: "auth")
            }
            isAuthenticating = false
        }
    }
}

// MARK: - Account Row

struct AccountRow: View {
    let account: SyncAccount
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(account.email)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text(account.domain)
                        .foregroundStyle(.secondary)

                    if let date = account.lastSyncDate {
                        Text("Synced \(date.formatted(.relative(presentation: .named)))")
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("Never synced")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
            }

            Spacer()

            if account.needsReauth {
                Label("Re-auth needed", systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove account")
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch account.lastSyncStatus {
        case .never:
            Image(systemName: "circle.dashed")
                .foregroundStyle(.secondary)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .inProgress:
            ProgressView()
                .controlSize(.small)
        }
    }
}
