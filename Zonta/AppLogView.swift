import AppKit
import SwiftUI

/// Debug window: leveled log on one tab, live job queue on the other. Long
/// Hermes requests show up here with a running timer and a Cancel button.
struct AppLogView: View {
    @ObservedObject private var log = AppLog.shared
    @ObservedObject private var queue = JobQueue.shared

    @State private var pane: Pane = .log
    @State private var minimumLevel: LogLevel? = nil
    @State private var search = ""

    private enum Pane: String { case log, jobs }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            HStack {
                Picker("", selection: $pane) {
                    Text("Log").tag(Pane.log)
                    Text("Jobs").tag(Pane.jobs)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)

                Spacer()

                if pane == .log {
                    Picker("Level", selection: $minimumLevel) {
                        Text("All").tag(nil as LogLevel?)
                        ForEach(LogLevel.allCases, id: \.self) { level in
                            Text(level.rawValue.capitalized).tag(level as LogLevel?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 110)
                    TextField("Filter…", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            Group {
                if pane == .log { logList } else { jobList }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
        }
        .frame(minWidth: 700, minHeight: 460)
        .glassSurface()
        .tint(Theme.accent)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title2)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("App Log")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                Text("\(log.entries.count) entries · \(warningCount) warnings · \(errorCount) errors")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            if queue.activeCount > 0 {
                Button {
                    Speak.stop()
                    queue.cancelAll()
                } label: {
                    Label("Cancel jobs", systemImage: "stop.circle")
                }
                .buttonStyle(AccentButtonStyle())
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(log.allText, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(AccentButtonStyle())
            Button {
                log.clear()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(AccentButtonStyle())
            Button {
                AppLogWindow.hide()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.borderless)
            .help("Close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var errorCount: Int { log.entries.filter { $0.level == .error }.count }
    private var warningCount: Int { log.entries.filter { $0.level == .warning }.count }

    // MARK: - Log

    /// Newest first: the latest line is always at the top.
    private var filtered: [LogEntry] {
        log.entries.filter { entry in
            if let minimumLevel, entry.level < minimumLevel { return false }
            if !search.isEmpty,
               !entry.message.localizedCaseInsensitiveContains(search),
               !entry.subsystem.localizedCaseInsensitiveContains(search)
            { return false }
            return true
        }
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered) { entry in
                        logRow(entry).id(entry.id)
                    }
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .onAppear { scrollToLatest(proxy, animated: false) }
            .onChange(of: log.entries.count) { _, _ in
                scrollToLatest(proxy, animated: true)
            }
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let newest = filtered.first else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(newest.id, anchor: .top)
            }
        } else {
            proxy.scrollTo(newest.id, anchor: .top)
        }
    }

    private func logRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.date, format: .dateTime.hour().minute().second())
                .font(.caption2.monospaced())
                .foregroundStyle(Theme.muted)
            Text(entry.level.symbol)
                .font(.caption.monospaced())
                .foregroundStyle(color(for: entry.level))
                .frame(width: 12)
            Text(entry.subsystem)
                .font(.caption.monospaced())
                .foregroundStyle(Theme.accent)
                .frame(width: 82, alignment: .leading)
            Text(entry.message)
                .font(.system(size: 12, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .debug: return Theme.muted
        case .info: return Theme.accent
        case .warning: return .orange
        case .error: return .red
        }
    }

    // MARK: - Jobs

    private var jobList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(queue.jobs) { job in
                    jobRow(job)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    private func jobRow(_ job: JobRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(for: job.state))
                .foregroundStyle(color(for: job.state))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(job.title).font(.body)
                    Spacer()
                    Text(job.lane.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text(job.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                    Text(job.enqueuedAt, format: .dateTime.hour().minute().second())
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if job.state == .running {
                        Button("Cancel") {
                            if job.lane == .speech { Speak.stop() }
                            queue.cancel(lane: job.lane)
                        }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                    }
                }
                if let error = job.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }

    private func icon(for state: JobState) -> String {
        switch state {
        case .queued: return "clock"
        case .running: return "ellipsis.circle"
        case .succeeded: return "checkmark.circle"
        case .failed: return "xmark.circle"
        case .cancelled: return "minus.circle"
        }
    }

    private func color(for state: JobState) -> Color {
        switch state {
        case .queued: return Theme.muted
        case .running: return Theme.accent
        case .succeeded: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(log.fileURL.path)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
            Button("Reveal log file") {
                NSWorkspace.shared.activateFileViewerSelecting([log.fileURL])
            }
            .buttonStyle(.link)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
