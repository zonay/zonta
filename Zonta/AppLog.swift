import Foundation

/// Severity of a log line. Ordered so filters can compare with `<`.
enum LogLevel: String, CaseIterable, Comparable {
    case debug, info, warning, error

    var priority: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        }
    }

    var symbol: String {
        switch self {
        case .debug: return "•"
        case .info: return "→"
        case .warning: return "!"
        case .error: return "✕"
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.priority < rhs.priority }
}

struct LogEntry: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let level: LogLevel
    let subsystem: String
    let message: String
}

/// One in-memory ring of log lines, mirrored to
/// `~/Library/Logs/Zonta/zonta.log` so a crash or a fresh build can still be
/// investigated. Newest entry is first, like the speech panel.
@MainActor
final class AppLog: ObservableObject {
    static let shared = AppLog()

    @Published private(set) var entries: [LogEntry] = []

    private let maxEntries = 1200
    let fileURL: URL

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Zonta", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("zonta.log")
        load()
    }

    // MARK: - Writing

    func log(_ level: LogLevel, _ message: String, subsystem: String = "Zonta") {
        let entry = LogEntry(
            id: UUID(), date: Date(), level: level,
            subsystem: subsystem, message: message
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        appendToFile(entry)
    }

    func debug(_ message: String, subsystem: String = "Zonta") {
        log(.debug, message, subsystem: subsystem)
    }

    func info(_ message: String, subsystem: String = "Zonta") {
        log(.info, message, subsystem: subsystem)
    }

    func warning(_ message: String, subsystem: String = "Zonta") {
        log(.warning, message, subsystem: subsystem)
    }

    func error(_ message: String, subsystem: String = "Zonta") {
        log(.error, message, subsystem: subsystem)
    }

    func clear() {
        entries.removeAll()
        try? Data().write(to: fileURL)
    }

    // MARK: - Reading / exporting

    func formatted(_ entry: LogEntry) -> String {
        "\(timeFormatter.string(from: entry.date))  \(entry.level.symbol) [\(entry.subsystem)] \(entry.message)"
    }

    /// Oldest first, ready to paste into an issue or a terminal.
    var allText: String {
        entries.reversed().map(formatted).joined(separator: "\n")
    }

    // MARK: - Persistence

    private func load() {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        for line in raw.split(separator: "\n").suffix(maxEntries) {
            let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
                .map(String.init)
            guard parts.count == 4,
                  let epoch = Double(parts[0]),
                  let level = LogLevel(rawValue: parts[1])
            else { continue }
            entries.append(LogEntry(
                id: UUID(), date: Date(timeIntervalSince1970: epoch),
                level: level, subsystem: parts[2], message: parts[3]
            ))
        }
        entries.reverse()
    }

    private func appendToFile(_ entry: LogEntry) {
        let flat = entry.message.replacingOccurrences(of: "\n", with: " ⏎ ")
        let line = "\(entry.date.timeIntervalSince1970)\t\(entry.level.rawValue)\t\(entry.subsystem)\t\(flat)\n"
        guard let data = line.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? Data().write(to: fileURL)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(data)
    }
}
