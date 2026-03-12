import AppKit
import Foundation
import os

/// Checks for app updates by fetching a JSON manifest from a remote URL.
///
/// Expected JSON format at the update URL:
/// ```json
/// {
///   "version": "1.1.0",
///   "build": "2",
///   "downloadURL": "https://example.com/MahisoftContactSync.dmg",
///   "releaseNotes": "Bug fixes and performance improvements."
/// }
/// ```
///
/// Host this JSON anywhere: GitHub Pages, S3, a gist, etc.
@Observable
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    enum CheckState {
        case idle
        case checking
        case upToDate
        case updateAvailable(version: String, notes: String?)
        case failed
    }

    private(set) var checkState: CheckState = .idle
    private(set) var availableVersion: String?
    private(set) var downloadURL: URL?
    private(set) var releaseNotes: String?
    private(set) var lastCheckError: String?

    var hasUpdate: Bool { availableVersion != nil }

    /// The URL to the update manifest JSON. Set this to your hosted endpoint.
    static let updateManifestURL = URL(string: "https://raw.githubusercontent.com/mahirick/Mahisoft-GAL-Sync/main/update.json")

    private static let backgroundCheckInterval: TimeInterval = 86400 // 24 hours
    private var backgroundTimer: Timer?

    private init() {}

    // MARK: - Background Scheduling

    func startBackgroundChecks() {
        backgroundTimer?.invalidate()
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: Self.backgroundCheckInterval, repeats: true) { _ in
            Task { @MainActor in
                await UpdateChecker.shared.check()
            }
        }
    }

    func stopBackgroundChecks() {
        backgroundTimer?.invalidate()
        backgroundTimer = nil
    }

    // MARK: - Public

    /// Force an update check regardless of timing.
    func check() async {
        guard let manifestURL = Self.updateManifestURL else {
            Logger.app.warning("Update manifest URL not configured")
            return
        }

        checkState = .checking
        lastCheckError = nil

        do {
            let (data, response) = try await URLSession.shared.data(from: manifestURL)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                let msg = "Server returned HTTP \(code)"
                Logger.app.warning("Update check: \(msg)")
                lastCheckError = msg
                checkState = .failed
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let remoteVersion = json["version"] as? String else {
                let msg = "Invalid update manifest format"
                Logger.app.warning("Update check: \(msg)")
                lastCheckError = msg
                checkState = .failed
                return
            }

            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            let notes = json["releaseNotes"] as? String

            if isVersion(remoteVersion, newerThan: currentVersion) {
                availableVersion = remoteVersion
                releaseNotes = notes

                if let urlString = json["downloadURL"] as? String ?? (json["url"] as? String) {
                    downloadURL = URL(string: urlString)
                }

                checkState = .updateAvailable(version: remoteVersion, notes: notes)
                Logger.app.info("Update available: \(remoteVersion) (current: \(currentVersion))")
            } else {
                availableVersion = nil
                downloadURL = nil
                releaseNotes = nil
                checkState = .upToDate
                Logger.app.info("App is up to date (\(currentVersion))")
            }
        } catch {
            lastCheckError = error.localizedDescription
            checkState = .failed
            Logger.app.warning("Update check failed: \(error.localizedDescription)")
        }
    }

    /// Runs a check and shows an NSAlert with the result. Use this for manual "Check for Updates..." actions.
    func checkAndAlert() async {
        await check()

        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let alert = NSAlert()
        alert.alertStyle = .informational

        switch checkState {
        case .upToDate:
            alert.messageText = "You're up to date!"
            alert.informativeText = "Version \(currentVersion) is the latest version."
            alert.addButton(withTitle: "OK")
            alert.runModal()

        case .updateAvailable(let version, let notes):
            alert.messageText = "Update Available — v\(version)"
            alert.informativeText = notes ?? "A new version is available."
            alert.addButton(withTitle: "Download Update")
            alert.addButton(withTitle: "Later")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                openDownloadPage()
            }

        case .failed:
            alert.messageText = "Update Check Failed"
            alert.informativeText = "Could not reach the update server.\n\n\(lastCheckError ?? "Unknown error")\n\nPlease check your internet connection and try again."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()

        default:
            break
        }
    }

    func openDownloadPage() {
        guard let url = downloadURL else { return }
        NSWorkspace.shared.open(url)
    }

    func dismiss() {
        availableVersion = nil
        checkState = .idle
    }

    // MARK: - Version Comparison

    /// Compares two semantic version strings (e.g., "1.2.0" > "1.1.3").
    private func isVersion(_ remote: String, newerThan local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }

        let maxLength = max(remoteParts.count, localParts.count)
        for i in 0..<maxLength {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }
}
