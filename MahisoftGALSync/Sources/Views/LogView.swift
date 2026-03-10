import SwiftUI

struct LogView: View {
    @Environment(LogStore.self) private var logStore

    @State private var filterLevel: LogStore.LogEntry.Level?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            logList
        }
        .frame(minWidth: 600, idealWidth: 700, minHeight: 400, idealHeight: 500)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Level", selection: $filterLevel) {
                Text("All").tag(LogStore.LogEntry.Level?.none)
                Label("Info", systemImage: "info.circle")
                    .tag(LogStore.LogEntry.Level?.some(.info))
                Label("Warnings", systemImage: "exclamationmark.triangle")
                    .tag(LogStore.LogEntry.Level?.some(.warning))
                Label("Errors", systemImage: "xmark.circle")
                    .tag(LogStore.LogEntry.Level?.some(.error))
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            Spacer()

            Button("Clear Log") {
                logStore.clear()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Log List

    private var logList: some View {
        Group {
            if filteredEntries.isEmpty {
                ContentUnavailableView {
                    Label("No Log Entries", systemImage: "doc.text")
                } description: {
                    Text(filterLevel == nil ? "Activity will appear here as the app runs." : "No entries match the selected filter.")
                }
            } else {
                List(filteredEntries) { entry in
                    LogEntryRow(entry: entry)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    private var filteredEntries: [LogStore.LogEntry] {
        let reversed = logStore.entries.reversed()
        if let level = filterLevel {
            return reversed.filter { $0.level == level }
        }
        return Array(reversed)
    }
}

// MARK: - Log Entry Row

struct LogEntryRow: View {
    let entry: LogStore.LogEntry

    private var icon: String {
        switch entry.level {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch entry.level {
        case .info: return .secondary
        case .warning: return .orange
        case .error: return .red
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .font(.body)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message)
                    .font(.body)
                    .lineLimit(3)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    Text(Self.dateFormatter.string(from: entry.date))
                    Text(entry.category)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
