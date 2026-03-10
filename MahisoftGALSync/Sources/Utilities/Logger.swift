import os

extension Logger {
    static let app = Logger(subsystem: Constants.bundleIdentifier, category: "app")
    static let auth = Logger(subsystem: Constants.bundleIdentifier, category: "auth")
    static let sync = Logger(subsystem: Constants.bundleIdentifier, category: "sync")
    static let contacts = Logger(subsystem: Constants.bundleIdentifier, category: "contacts")
}
