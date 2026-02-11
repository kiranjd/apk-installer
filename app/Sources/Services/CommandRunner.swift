import Foundation
import os

struct CommandResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32

    var combinedOutput: String {
        if stderr.isEmpty {
            return stdout
        }
        if stdout.isEmpty {
            return stderr
        }
        return "\(stdout)\n\(stderr)"
    }
}

enum CommandRunnerError: LocalizedError {
    case executableNotFound(String)
    case nonZeroExit(executable: String, exitCode: Int32, output: String)
    case timedOut(executable: String, timeout: TimeInterval)
    case cancelled(executable: String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let executable):
            return "Executable not found: \(executable)"
        case .nonZeroExit(let executable, let code, let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "\(executable) exited with status \(code)."
            }
            return "\(executable) exited with status \(code): \(trimmed)"
        case .timedOut(let executable, let timeout):
            return "\(executable) timed out after \(timeout)s."
        case .cancelled(let executable):
            return "\(executable) was cancelled."
        }
    }
}

enum CommandRunner {
    private static let logger = Logger(subsystem: "io.github.apkinstaller.mac", category: "CommandRunner")

    static func run(
        executable: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        workingDirectory: URL? = nil,
        timeout: TimeInterval? = 60,
        allowNonZeroExit: Bool = false
    ) async throws -> CommandResult {
        var mergedEnvironment = ProcessInfo.processInfo.environment
        environment.forEach { mergedEnvironment[$0.key] = $0.value }

        let resolvedExecutable = try resolveExecutable(executable, environment: mergedEnvironment)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedExecutable)
        process.arguments = arguments
        process.environment = mergedEnvironment
        process.currentDirectoryURL = workingDirectory

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let commandLabel = ([resolvedExecutable] + arguments).joined(separator: " ")

        do {
            try process.run()
        } catch {
            throw error
        }

        // Drain stdout/stderr concurrently while process is running.
        // Read on a background queue so a MainActor caller cannot block timeouts/cancellation.
        let stdoutTask = Task { await readDataToEndAsync(stdoutPipe.fileHandleForReading) }
        let stderrTask = Task { await readDataToEndAsync(stderrPipe.fileHandleForReading) }

        let terminationTask = Task { () throws -> CommandResult in
            let exitCode = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus)
                }
            }
            let stdoutData = await stdoutTask.value
            let stderrData = await stderrTask.value
            let stdout = String(decoding: stdoutData, as: UTF8.self)
            let stderr = String(decoding: stderrData, as: UTF8.self)
            return CommandResult(stdout: stdout, stderr: stderr, exitCode: exitCode)
        }

        do {
            let result = try await withTaskCancellationHandler(operation: {
                try await runWithTimeout(
                    task: terminationTask,
                    process: process,
                    commandLabel: commandLabel,
                    timeout: timeout
                )
            }, onCancel: {
                if process.isRunning {
                    process.terminate()
                }
                terminationTask.cancel()
                stdoutTask.cancel()
                stderrTask.cancel()
            })

            if !allowNonZeroExit && result.exitCode != 0 {
                throw CommandRunnerError.nonZeroExit(
                    executable: commandLabel,
                    exitCode: result.exitCode,
                    output: result.combinedOutput
                )
            }

            return result
        } catch is CancellationError {
            if process.isRunning {
                process.terminate()
            }
            terminationTask.cancel()
            stdoutTask.cancel()
            stderrTask.cancel()
            throw CommandRunnerError.cancelled(executable: commandLabel)
        } catch {
            if process.isRunning {
                process.terminate()
            }
            terminationTask.cancel()
            stdoutTask.cancel()
            stderrTask.cancel()
            throw error
        }
    }

    static func findExecutable(named executable: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if executable.contains("/") {
            return FileManager.default.isExecutableFile(atPath: executable) ? executable : nil
        }

        let pathValue = environment["PATH"] ?? ""
        for folder in pathValue.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(folder)).appendingPathComponent(executable).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func runWithTimeout(
        task: Task<CommandResult, Error>,
        process: Process,
        commandLabel: String,
        timeout: TimeInterval?
    ) async throws -> CommandResult {
        guard let timeout, timeout > 0 else {
            return try await task.value
        }

        return try await withThrowingTaskGroup(of: CommandResult.self) { group in
            group.addTask {
                try await task.value
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if process.isRunning {
                    process.terminate()
                }
                throw CommandRunnerError.timedOut(executable: commandLabel, timeout: timeout)
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private static func readDataToEndAsync(_ fileHandle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let data = fileHandle.readDataToEndOfFile()
                continuation.resume(returning: data)
            }
        }
    }

    private static func resolveExecutable(_ executable: String, environment: [String: String]) throws -> String {
        if let resolved = findExecutable(named: executable, environment: environment) {
            return resolved
        }

        logger.error("Executable not found: \(executable, privacy: .public)")
        throw CommandRunnerError.executableNotFound(executable)
    }
}
