import Foundation

/// LAN HTTP via /usr/bin/curl.
///
/// URLSession from an ad-hoc menu-bar app is blocked by Local Network Privacy
/// and surfaces as NSURLErrorNotConnectedToInternet ("The Internet connection
/// appears to be offline"). /usr/bin/curl is already allowed on this machine.
///
/// The process wait is async and cancellable: a Hermes reply can take minutes,
/// and neither the UI nor the job queue may block while waiting for it.
enum HTTP {
    struct Response {
        let status: Int
        let body: Data
        /// Response headers, names lowercased. A server that holds the
        /// conversation on its side (Hermes) hands the session id back here.
        let headers: [String: String]
    }

    static func post(
        url: URL,
        headers: [String: String] = [:],
        body: Data,
        timeout: TimeInterval
    ) async throws -> Response {
        try await run(url: url, headers: headers, body: body, timeout: timeout, method: "POST")
    }

    static func get(
        url: URL,
        headers: [String: String] = [:],
        timeout: TimeInterval = 10
    ) async throws -> Response {
        try await run(url: url, headers: headers, body: nil, timeout: timeout, method: "GET")
    }

    /// `Process` is not Sendable, but this handle only touches it from the
    /// cancellation handler and is guarded by the process's own state.
    private final class ProcessHandle: @unchecked Sendable {
        let process: Process
        init(_ process: Process) { self.process = process }
        func interrupt() {
            if process.isRunning { process.interrupt() }
        }
    }

    private static func run(
        url: URL,
        headers: [String: String],
        body: Data?,
        timeout: TimeInterval,
        method: String
    ) async throws -> Response {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zonta-http-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let payload = dir.appendingPathComponent("body")
        let output = dir.appendingPathComponent("out")
        let headerFile = dir.appendingPathComponent("headers")
        if let body { try body.write(to: payload) }

        var args = [
            "--silent", "--show-error",
            "--max-time", String(Int(timeout.rounded(.up))),
            "--output", output.path,
            "--dump-header", headerFile.path,
            "--write-out", "%{http_code}",
            "--request", method,
        ]
        if body != nil {
            args.append(contentsOf: ["--data-binary", "@\(payload.path)"])
        }
        for (name, value) in headers {
            args.append(contentsOf: ["--header", "\(name): \(value)"])
        }
        args.append(url.absoluteString)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = args
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let host = url.host ?? url.absoluteString
        do {
            try process.run()
        } catch {
            await AppLog.shared.error("curl could not start for \(host): \(error.localizedDescription)", subsystem: "HTTP")
            throw error
        }
        await AppLog.shared.debug("\(method) \(host)\(url.path)", subsystem: "HTTP")

        let handle = ProcessHandle(process)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                handle.process.terminationHandler = { _ in continuation.resume() }
            }
        } onCancel: {
            handle.interrupt()
        }
        if Task.isCancelled { throw CancellationError() }

        let statusString = String(
            data: stdout.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errText = String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            let message = errText.isEmpty
                ? "Can't reach \(host)."
                : "Can't reach \(host). \(errText)"
            await AppLog.shared.warning(message, subsystem: "HTTP")
            throw NSError(domain: "Zonta", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }

        let status = Int(statusString) ?? 0
        let data = (try? Data(contentsOf: output)) ?? Data()
        if !(200..<300).contains(status) {
            let text = String(data: data, encoding: .utf8) ?? errText
            await AppLog.shared.error("HTTP \(status) from \(host): \(text.prefix(200))", subsystem: "HTTP")
            throw APIError.http(status, String(text.prefix(400)))
        }
        await AppLog.shared.debug("\(method) \(host) → \(status) (\(data.count) bytes)", subsystem: "HTTP")
        return Response(
            status: status,
            body: data,
            headers: parseHeaders(at: headerFile)
        )
    }

    /// Reads the header block curl dumped. curl writes one block per
    /// response, so a proxy CONNECT or a 100-continue leaves earlier blocks
    /// in the file. The last one is the answer we got.
    private static func parseHeaders(at url: URL) -> [String: String] {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        var headers: [String: String] = [:]
        for block in text.components(separatedBy: "\n\n") {
            let lines = block
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map(String.init)
            guard let first = lines.first, first.uppercased().hasPrefix("HTTP/") else { continue }
            headers = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { headers[name] = value }
            }
        }
        return headers
    }
}
