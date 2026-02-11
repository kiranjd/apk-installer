import Foundation

actor InstallOperationLogger {
    let logFilePath: String

    private var fileHandle: FileHandle?
    private let lineTimestampFormatter: ISO8601DateFormatter
    private let sessionStartTime: Date
    private static let maxLoggedOutputCharacters = 16_000

    private init(logFilePath: String, fileHandle: FileHandle) {
        self.logFilePath = logFilePath
        self.fileHandle = fileHandle
        self.sessionStartTime = Date()
        self.lineTimestampFormatter = ISO8601DateFormatter()
        self.lineTimestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    static func make(apkPath: String, isUpdate: Bool, deviceID: String?) -> InstallOperationLogger? {
        let fm = FileManager.default
        let rootLogsDirectory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("APKInstaller")
            .appendingPathComponent("installs")

        do {
            try fm.createDirectory(at: rootLogsDirectory, withIntermediateDirectories: true)

            let fileName = buildLogFileName(apkPath: apkPath, isUpdate: isUpdate, deviceID: deviceID)
            let fileURL = rootLogsDirectory.appendingPathComponent(fileName)
            fm.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)

            let handle = try FileHandle(forWritingTo: fileURL)
            return InstallOperationLogger(logFilePath: fileURL.path, fileHandle: handle)
        } catch {
            return nil
        }
    }

    func recordStart(apkPath: String, isUpdate: Bool, deviceID: String?, fallbackPackageIdentifier: String) {
        append("SESSION START")
        append("apk_path=\(apkPath)")
        append("mode=\(isUpdate ? "update" : "install")")
        append("device_id=\(deviceID ?? "<auto>")")
        append("fallback_package_id=\(fallbackPackageIdentifier)")
    }

    func recordProgress(_ message: String) {
        append("STAGE \(message)")
    }

    func recordCommandStart(command: String, timeout: TimeInterval) {
        append("CMD START timeout=\(formatSeconds(timeout)) command=\(command)")
    }

    func recordCommandResult(command: String, duration: TimeInterval, result: CommandResult) {
        append("CMD END exit=\(result.exitCode) duration=\(formatSeconds(duration)) command=\(command)")
        if !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendMultiline("STDOUT", result.stdout)
        }
        if !result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendMultiline("STDERR", result.stderr)
        }
    }

    func recordCommandFailure(command: String, duration: TimeInterval, error: Error) {
        append("CMD ERROR duration=\(formatSeconds(duration)) command=\(command) error=\(error.localizedDescription)")
    }

    func recordOutcome(_ outcome: String, detail: String? = nil) {
        if let detail, !detail.isEmpty {
            append("SESSION \(outcome) detail=\(detail)")
        } else {
            append("SESSION \(outcome)")
        }
    }

    func close() {
        guard let fileHandle else { return }
        try? fileHandle.synchronize()
        try? fileHandle.close()
        self.fileHandle = nil
    }

    private func append(_ line: String) {
        guard let fileHandle else { return }
        let timestamp = lineTimestampFormatter.string(from: Date())
        let elapsed = Date().timeIntervalSince(sessionStartTime)
        let fullLine = "[\(timestamp)] [+\(formatSeconds(elapsed))] \(line)\n"
        if let data = fullLine.data(using: .utf8) {
            do {
                try fileHandle.seekToEnd()
                try fileHandle.write(contentsOf: data)
                try fileHandle.synchronize()
            } catch {
                // Intentionally ignore logging failures to avoid impacting install flow.
            }
        }
    }

    private func appendMultiline(_ prefix: String, _ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let payload = truncate(trimmed)
        for line in payload.split(whereSeparator: \.isNewline) {
            append("\(prefix) \(String(line))")
        }
    }

    private func truncate(_ text: String) -> String {
        guard text.count > Self.maxLoggedOutputCharacters else { return text }
        let prefix = text.prefix(Self.maxLoggedOutputCharacters)
        return "\(prefix)\n... <truncated \(text.count - Self.maxLoggedOutputCharacters) chars>"
    }

    private static func buildLogFileName(apkPath: String, isUpdate: Bool, deviceID: String?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"

        let timestamp = formatter.string(from: Date())
        let apkName = sanitizeName(URL(fileURLWithPath: apkPath).deletingPathExtension().lastPathComponent)
        let device = sanitizeName(deviceID ?? "auto")
        let mode = isUpdate ? "update" : "install"
        return "\(timestamp)-\(mode)-\(apkName)-\(device).log"
    }

    private static func sanitizeName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalarView = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let sanitized = String(scalarView)
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return sanitized.isEmpty ? "unknown" : sanitized
    }

    private func formatSeconds(_ value: TimeInterval) -> String {
        String(format: "%.2fs", value)
    }
}
