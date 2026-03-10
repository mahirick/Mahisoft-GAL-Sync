import SwiftUI

extension Notification.Name {
    static let showHowItWorks = Notification.Name("showHowItWorks")
}

struct PreferencesView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            AccountsTab()
                .tag(0)
                .tabItem {
                    Label("Accounts", systemImage: "person.2")
                }

            SyncSettingsTab()
                .tag(1)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }

            HowItWorksTab()
                .tag(2)
                .tabItem {
                    Label("How It Works", systemImage: "questionmark.circle")
                }

            AboutTab()
                .tag(3)
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 560, height: 480)
        .onReceive(NotificationCenter.default.publisher(for: .showHowItWorks)) { _ in
            selectedTab = 2
        }
    }
}
