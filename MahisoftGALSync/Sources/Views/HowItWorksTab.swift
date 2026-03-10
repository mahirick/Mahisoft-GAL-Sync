import SwiftUI

struct HowItWorksTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("How Mahisoft GAL Sync Works")
                        .font(.title2.bold())
                    Text("Keep your Apple Contacts in sync with your company's Google Workspace directory.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Purpose
                sectionHeader("What It Does", icon: "arrow.triangle.2.circlepath.circle.fill")
                Text("Mahisoft GAL Sync pulls your organization's people directory from Google Workspace and writes it into Apple Contacts. Every coworker — with their name, email, phone, title, and photo — stays up to date automatically.")
                    .font(.callout)

                // Steps
                sectionHeader("The Process", icon: "list.number")

                step(number: 1, title: "Connect Your Account",
                     detail: "Sign in with your Google Workspace account. The app opens your browser for a secure Google sign-in — it never sees your password.")

                step(number: 2, title: "Fetch the Directory",
                     detail: "The app calls the Google People API (or Admin SDK for workspace admins) to download the company directory — names, emails, phones, titles, departments, and photos.")

                step(number: 3, title: "Sync to Apple Contacts",
                     detail: "Each person is matched by email. New people are added, changes are updated, and removed employees are cleaned up. All contacts go into a dedicated group (\"Mahisoft GAL\") so they never mix with your personal contacts.")

                step(number: 4, title: "Stay Current",
                     detail: "The app syncs on a schedule (default: every 4 hours). It detects changes so unchanged directories are skipped. You can also hit Sync Now anytime.")

                Divider()

                // Privacy
                sectionHeader("Privacy & Security", icon: "lock.shield.fill")

                bulletPoint("Your Google credentials are stored in the macOS Keychain — never written to disk.")
                bulletPoint("The app only requests read-only access to the directory. It cannot modify your Google account.")
                bulletPoint("Contacts are only written to the managed group. Your personal contacts are never touched.")
                bulletPoint("All communication uses HTTPS. OAuth uses PKCE for secure token exchange.")

                Divider()

                // Tips
                sectionHeader("Good to Know", icon: "lightbulb.fill")

                bulletPoint("Non-admin users see the same directory contacts visible in Google Contacts. Admins can see the full org.")
                bulletPoint("If you remove an account, synced contacts stay in Apple Contacts — they just stop updating.")
                bulletPoint("The app runs as a menu bar icon with no Dock presence. Set it to launch at login and forget about it.")

            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Components

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
    }

    private func step(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(Circle().fill(.blue))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.bold())
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\u{2022}")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
