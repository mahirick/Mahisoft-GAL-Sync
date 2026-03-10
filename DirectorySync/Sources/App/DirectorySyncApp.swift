import AppKit
import SwiftUI

@main
struct DirectorySyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var orchestrator = SyncOrchestrator.shared
    @State private var logStore = LogStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(orchestrator)
                .environment(logStore)
        } label: {
            MenuBarIcon(iconName: menuBarIconName)
        }

        Window("Mahisoft GAL Sync", id: "preferences") {
            PreferencesView()
                .environment(orchestrator)
                .environment(logStore)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Activity Log", id: "log") {
            LogView()
                .environment(logStore)
        }
        .defaultSize(width: 700, height: 500)
        .defaultPosition(.center)
    }

    private var menuBarIconName: String {
        if orchestrator.isSyncing {
            return "arrow.triangle.2.circlepath"
        }
        if orchestrator.hasAccountsNeedingReauth {
            return "person.2.badge.exclamationmark"
        }
        return "person.2.fill"
    }
}

/// Renders an SF Symbol as a template NSImage for the menu bar.
/// Template images automatically adapt to light/dark mode (white on dark, black on light).
struct MenuBarIcon: View {
    let iconName: String

    var body: some View {
        Image(nsImage: templateMenuBarImage(systemName: iconName))
    }

    private func templateMenuBarImage(systemName: String) -> NSImage {
        let pointSize: CGFloat = 22  // Maximum size that fits the menu bar
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)

        guard let symbol = NSImage(systemSymbolName: systemName, accessibilityDescription: "Mahisoft GAL Sync")?
            .withSymbolConfiguration(config) else {
            return NSImage()
        }

        symbol.isTemplate = true
        return symbol
    }
}
