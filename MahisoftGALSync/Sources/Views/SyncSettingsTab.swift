import SwiftUI
import ServiceManagement
import os

struct SyncSettingsTab: View {
    @AppStorage("syncIntervalHours") private var syncIntervalHours = Constants.Defaults.syncIntervalHours
    @AppStorage("contactGroupName") private var contactGroupName = Constants.Defaults.contactGroupName
    @AppStorage("separateGroupPerDomain") private var separateGroupPerDomain = Constants.Defaults.separateGroupPerDomain
    @AppStorage("removeDeletedContacts") private var removeDeletedContacts = Constants.Defaults.removeDeletedContacts
    @AppStorage("syncOnLaunch") private var syncOnLaunch = Constants.Defaults.syncOnLaunch
    @AppStorage("includeProfilePhotos") private var includeProfilePhotos = Constants.Defaults.includeProfilePhotos
    @AppStorage("launchAtLogin") private var launchAtLogin = Constants.Defaults.launchAtLogin

    @Environment(SyncOrchestrator.self) private var orchestrator
    @Environment(LogStore.self) private var logStore

    var body: some View {
        Form {
            Section {
                Picker("Sync interval:", selection: $syncIntervalHours) {
                    Text("Every hour").tag(1)
                    Text("Every 4 hours").tag(4)
                    Text("Every 12 hours").tag(12)
                    Text("Every 24 hours").tag(24)
                }
                .onChange(of: syncIntervalHours) { _, newValue in
                    orchestrator.startScheduledSync(intervalHours: newValue)
                    logStore.info("Sync interval changed to \(newValue) hours", category: "settings")
                }

                Toggle("Sync when app launches", isOn: $syncOnLaunch)

                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        updateLaunchAtLogin(enabled: newValue)
                    }
            } header: {
                Text("Schedule")
            }

            Section {
                TextField("Contact group name:", text: $contactGroupName)
                    .textFieldStyle(.roundedBorder)

                Toggle("Create separate group per domain", isOn: $separateGroupPerDomain)
                    .help("When enabled, contacts from each domain get their own group (e.g. \"Acme GAL\", \"Corp GAL\")")

                Toggle("Remove contacts deleted from directory", isOn: $removeDeletedContacts)
                    .help("When enabled, contacts removed from the Google directory are removed from the synced group (the contact itself is not deleted)")
            } header: {
                Text("Contacts")
            }

            Section {
                Toggle("Include profile photos", isOn: $includeProfilePhotos)
                    .help("Download and set Google profile photos on contacts")
            } header: {
                Text("Directory")
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private func updateLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                logStore.info("Registered for launch at login", category: "settings")
            } else {
                try SMAppService.mainApp.unregister()
                logStore.info("Unregistered from launch at login", category: "settings")
            }
        } catch {
            logStore.log(error, context: "Updating launch at login", category: "settings")
        }
    }
}
