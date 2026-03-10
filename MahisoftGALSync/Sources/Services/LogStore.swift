import Foundation
import os

/// Persistent, observable log store for surfacing errors and events to the user.
/// Writes to Application Support and keeps the most recent 500 entries.
@Observable
@MainActor
final class LogStore {
    static let shared = LogStore()

    private(set) var entries: [LogEntry] = []
    private let maxEntries = 500

    private static let storageURL: URL = {
        Constants.appSupportDirectory.appendingPathComponent("activity_log.json")
    }()

    struct LogEntry: Identifiable, Codable {
        let id: UUID
        let date: Date
        let level: Level
        let category: String
        let message: String

        enum Level: String, Codable {
            case info
            case warning
            case error
        }

        init(level: Level, category: String, message: String) {
            self.id = UUID()
            self.date = Date()
            self.level = level
            self.category = category
            self.message = message
        }
    }

    private init() {
        load()
    }

    // MARK: - Logging

    func info(_ message: String, category: String = "app") {
        append(LogEntry(level: .info, category: category, message: message))
        Logger.app.info("\(message)")
    }

    func warning(_ message: String, category: String = "app") {
        append(LogEntry(level: .warning, category: category, message: message))
        Logger.app.warning("\(message)")
    }

    func error(_ message: String, category: String = "app") {
        append(LogEntry(level: .error, category: category, message: message))
        Logger.app.error("\(message)")
    }

    func log(_ error: Error, context: String, category: String = "app") {
        let message = "\(context): \(error.localizedDescription)"
        append(LogEntry(level: .error, category: category, message: message))
        Logger.app.error("\(message)")
    }

    var hasErrors: Bool {
        entries.contains { $0.level == .error }
    }

    var recentErrors: [LogEntry] {
        entries.filter { $0.level == .error }.suffix(10).reversed()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    // MARK: - Persistence

    private func append(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.storageURL),
              let decoded = try? JSONDecoder().decode([LogEntry].self, from: data) else {
            return
        }
        entries = decoded
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: Self.storageURL, options: .atomic)
        } catch {
            Logger.app.error("Failed to persist log store: \(error.localizedDescription)")
        }
    }
}
