import Foundation
import os

public struct ADBDevice: Identifiable, Equatable {
    public enum Status: String {
        case device
        case offline
        case unauthorized
        case unknown
        case bootloader
        case recovery
        case sideload
    }

    public let id: String
    public let status: Status
    public let product: String?
    public let model: String?
    public let device: String?
    public let transportId: String?

    public var displayName: String {
        var parts = [id]
        if let model {
            parts.append("(\(model))")
        }
        if status != .device {
            parts.append("[\(status.rawValue)]")
        }
        return parts.joined(separator: " ")
    }
}

struct ADBPathDetectionReport {
    let resolvedPath: String?
    let checkedPaths: [String]
}

struct ADBInstallResult {
    let packageIdentifier: String?
    let didRemoveExisting: Bool
    let installLogPath: String?
}

enum ADBService {
    private static let logger = Logger(subsystem: "io.github.apkinstaller.mac", category: "ADBService")
    static let checkedPathsUserInfoKey = "checked_paths"
    static let installLogPathUserInfoKey = "install_log_path"

    @TaskLocal
    private static var activeInstallLogger: InstallOperationLogger?

    static func detectADBPath() async -> String? {
        let report = await detectADBPathWithReport()
        if let resolved = report.resolvedPath {
            StorageManager.saveADBPath(resolved)
        }
        return report.resolvedPath
    }

    static func detectADBPathWithReport() async -> ADBPathDetectionReport {
        let environment = runtimeEnvironment()
        let candidates = buildADBCandidates(environment: environment)

        for candidate in candidates where await isUsableADBExecutable(atPath: candidate, environment: environment) {
            return ADBPathDetectionReport(resolvedPath: candidate, checkedPaths: candidates)
        }

        return ADBPathDetectionReport(resolvedPath: nil, checkedPaths: candidates)
    }

    static func listDevices() async throws -> [ADBDevice] {
        let adbExecutable = try await adbExecutablePath()
        let result = try await runADB(arguments: ["devices", "-l"], executable: adbExecutable, timeout: 20)
        return parseDevicesOutput(result.stdout)
    }

    static func adbVersion() async throws -> String {
        let adbExecutable = try await adbExecutablePath()
        return try await adbVersion(atPath: adbExecutable)
    }

    static func adbVersion(atPath adbExecutable: String) async throws -> String {
        let result = try await runADB(arguments: ["version"], executable: adbExecutable, timeout: 20)
        return parseADBVersionOutput(result.combinedOutput)
    }

    static func installAPK(
        path: String,
        isUpdate: Bool,
        deviceID: String?,
        fallbackPackageIdentifier: String,
        onProgress: ((String) async -> Void)? = nil,
        onLogReady: ((String) async -> Void)? = nil
    ) async throws -> ADBInstallResult {
        let operationLogger = InstallOperationLogger.make(apkPath: path, isUpdate: isUpdate, deviceID: deviceID)
        let logPath = operationLogger?.logFilePath
        if let logPath {
            await onLogReady?(logPath)
        }

        return try await runInstallWithLogger(
            operationLogger,
            apkPath: path,
            isUpdate: isUpdate,
            deviceID: deviceID,
            fallbackPackageIdentifier: fallbackPackageIdentifier,
            onProgress: onProgress
        )
    }

    private static func runInstallWithLogger(
        _ operationLogger: InstallOperationLogger?,
        apkPath: String,
        isUpdate: Bool,
        deviceID: String?,
        fallbackPackageIdentifier: String,
        onProgress: ((String) async -> Void)?
    ) async throws -> ADBInstallResult {
        let execute = {
            try await executeInstallAPK(
                path: apkPath,
                isUpdate: isUpdate,
                deviceID: deviceID,
                fallbackPackageIdentifier: fallbackPackageIdentifier,
                onProgress: onProgress,
                installLogPath: operationLogger?.logFilePath
            )
        }

        guard let operationLogger else {
            return try await execute()
        }

        return try await $activeInstallLogger.withValue(operationLogger) {
            await operationLogger.recordStart(
                apkPath: apkPath,
                isUpdate: isUpdate,
                deviceID: deviceID,
                fallbackPackageIdentifier: fallbackPackageIdentifier
            )
            do {
                let result = try await execute()
                await operationLogger.recordOutcome("SUCCESS")
                await operationLogger.close()
                return result
            } catch {
                if error is CancellationError || isCommandCancellation(error) {
                    await operationLogger.recordOutcome("CANCELLED", detail: error.localizedDescription)
                    await operationLogger.close()
                    throw error
                }

                await operationLogger.recordOutcome("FAILED", detail: error.localizedDescription)
                await operationLogger.close()
                throw attachInstallLogPath(error, logPath: operationLogger.logFilePath)
            }
        }
    }

    private static func executeInstallAPK(
        path: String,
        isUpdate: Bool,
        deviceID: String?,
        fallbackPackageIdentifier: String,
        onProgress: ((String) async -> Void)?,
        installLogPath: String?
    ) async throws -> ADBInstallResult {
        let adbExecutable = try await adbExecutablePath()
        let trimmedFallback = normalizedFallbackPackageIdentifier(fallbackPackageIdentifier)

        var arguments: [String] = []
        if let deviceID {
            arguments.append(contentsOf: ["-s", deviceID])
        }
        arguments.append("install")
        arguments.append("-t")
        if isUpdate {
            arguments.append("-r")
        }
        arguments.append(path)

        await reportProgress(isUpdate ? "Updating existing app…" : "Installing new app…", onProgress: onProgress)
        do {
            try await withInstallDeadline(seconds: 120, stage: isUpdate ? "Update APK" : "Install APK") {
                let initialInstallResult = try await runADBWithTransientDeviceRetry(
                    arguments: arguments,
                    executable: adbExecutable,
                    timeout: 90,
                    allowNonZeroExit: true
                )

                if initialInstallResult.exitCode != 0 {
                    let lowered = initialInstallResult.combinedOutput.lowercased()
                    let shouldRetryWithReplace = !isUpdate && (
                        lowered.contains("install_failed_already_exists")
                            || lowered.contains("install_failed_update_incompatible")
                    )

                    if shouldRetryWithReplace {
                        var replaceArguments: [String] = []
                        if let deviceID {
                            replaceArguments.append(contentsOf: ["-s", deviceID])
                        }
                        replaceArguments.append(contentsOf: ["install", "-t", "-r", path])
                        await reportProgress("Installing app (replace mode)…", onProgress: onProgress)

                        let replaceResult = try await runADBWithTransientDeviceRetry(
                            arguments: replaceArguments,
                            executable: adbExecutable,
                            timeout: 90,
                            allowNonZeroExit: true
                        )
                        guard replaceResult.exitCode == 0 else {
                            throw CommandRunnerError.nonZeroExit(
                                executable: ([adbExecutable] + replaceArguments).joined(separator: " "),
                                exitCode: replaceResult.exitCode,
                                output: replaceResult.combinedOutput
                            )
                        }
                    } else {
                        throw CommandRunnerError.nonZeroExit(
                            executable: ([adbExecutable] + arguments).joined(separator: " "),
                            exitCode: initialInstallResult.exitCode,
                            output: initialInstallResult.combinedOutput
                        )
                    }
                }
            }
        } catch {
            throw contextualizedInstallError(error, stage: isUpdate ? "Update APK" : "Install APK")
        }

        // Keep core path strict: install/update must complete without waiting on peripheral work.
        // Any package-id resolution and app launch are best-effort, detached post-success tasks.
        let shouldSkipPostInstallLaunch = runtimeEnvironment()["APKINSTALLER_SKIP_POST_INSTALL_LAUNCH"] == "1"
        if !shouldSkipPostInstallLaunch {
            let launchExecutable = adbExecutable
            let launchDeviceID = deviceID
            let launchLogger = activeInstallLogger
            let launchFallbackIdentifier = trimmedFallback
            let launchAPKPath = path
            Task.detached(priority: .utility) {
                var launchIdentifier = launchFallbackIdentifier
                if let resolved = try? await packageIdentifier(from: launchAPKPath),
                   !resolved.isEmpty {
                    launchIdentifier = resolved
                }

                guard let launchIdentifier else { return }
                await launchLogger?.recordProgress("Best-effort launch for \(launchIdentifier)")
                _ = try? await launchApp(
                    identifier: launchIdentifier,
                    deviceID: launchDeviceID,
                    executable: launchExecutable
                )
            }
        }

        return ADBInstallResult(
            packageIdentifier: nil,
            didRemoveExisting: false,
            installLogPath: installLogPath
        )
    }

    private static func withInstallDeadline(
        seconds: TimeInterval,
        stage: String,
        operation: @escaping () async throws -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CommandRunnerError.timedOut(executable: stage, timeout: seconds)
            }

            _ = try await group.next()
            group.cancelAll()
        }
    }

    static func clearAppData(identifier: String, deviceID: String?) async throws {
        let adbExecutable = try await adbExecutablePath()

        var arguments: [String] = []
        if let deviceID {
            arguments.append(contentsOf: ["-s", deviceID])
        }
        arguments.append(contentsOf: ["shell", "pm", "clear", identifier])

        _ = try await runADB(arguments: arguments, executable: adbExecutable, timeout: 60)
    }

    static func packageIdentifier(from apkPath: String) async throws -> String {
        let environment = runtimeEnvironment()
        do {
            let aaptExecutable = detectAAPTPath(environment: environment)
            let result = try await runLoggedCommand(
                executable: aaptExecutable,
                arguments: ["dump", "badging", apkPath],
                environment: environment,
                timeout: 15
            )
            return try parsePackageIdentifierFromBadging(result.stdout)
        } catch {
            let firstError = error
            if let aapt2Executable = detectAAPT2Path(environment: environment) {
                if let packageID = try? await packageIdentifierUsingAAPT2(apkPath: apkPath, executable: aapt2Executable, environment: environment) {
                    return packageID
                }
            }

            if let apkanalyzer = detectApkAnalyzerPath(environment: environment) {
                let result = try await runLoggedCommand(
                    executable: apkanalyzer,
                    arguments: ["manifest", "application-id", apkPath],
                    environment: environment,
                    timeout: 15
                )
                let packageID = result.stdout
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: .newlines)
                    .first?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !packageID.isEmpty {
                    return packageID
                }
            }

            throw firstError
        }
    }

    private static func uninstallApp(identifier: String, deviceID: String?, executable: String) async throws -> CommandResult {
        var arguments: [String] = []
        if let deviceID {
            arguments.append(contentsOf: ["-s", deviceID])
        }
        arguments.append(contentsOf: ["uninstall", identifier])
        return try await runADB(arguments: arguments, executable: executable, timeout: 60)
    }

    private static func uninstallIfPresent(identifier: String, deviceID: String?, executable: String) async throws -> Bool {
        var arguments: [String] = []
        if let deviceID {
            arguments.append(contentsOf: ["-s", deviceID])
        }
        arguments.append(contentsOf: ["uninstall", identifier])

        let result = try await runADBWithTransientDeviceRetry(
            arguments: arguments,
            executable: executable,
            timeout: 20,
            allowNonZeroExit: true
        )

        if result.exitCode == 0 {
            return true
        }

        let lowered = result.combinedOutput.lowercased()
        if lowered.contains("unknown package")
            || lowered.contains("not installed")
            || lowered.contains("delete_failed_internal_error") {
            return false
        }

        throw CommandRunnerError.nonZeroExit(
            executable: "adb uninstall \(identifier)",
            exitCode: result.exitCode,
            output: result.combinedOutput
        )
    }

    private static func launchApp(identifier: String, deviceID: String?, executable: String) async throws -> CommandResult {
        // Most reliable path: ask ActivityManager to launch the package's MAIN/LAUNCHER activity.
        var packageStartArguments: [String] = []
        if let deviceID {
            packageStartArguments.append(contentsOf: ["-s", deviceID])
        }
        packageStartArguments.append(contentsOf: [
            "shell",
            "am",
            "start",
            "-W",
            "-a", "android.intent.action.MAIN",
            "-c", "android.intent.category.LAUNCHER",
            "-p", identifier
        ])

        let packageStartResult = try await runADB(
            arguments: packageStartArguments,
            executable: executable,
            timeout: 10,
            allowNonZeroExit: true
        )
        if packageStartResult.exitCode == 0,
           !containsLaunchFailure(packageStartResult.combinedOutput),
           try await waitForAppForeground(identifier: identifier, deviceID: deviceID, executable: executable) {
            return packageStartResult
        }

        if let launcherActivity = try await resolveLauncherActivity(
            identifier: identifier,
            deviceID: deviceID,
            executable: executable
        ) {
            var startArguments: [String] = []
            if let deviceID {
                startArguments.append(contentsOf: ["-s", deviceID])
            }
            startArguments.append(contentsOf: [
                "shell",
                "am",
                "start",
                "-W",
                "-n",
                launcherActivity
            ])

            let startResult = try await runADB(
                arguments: startArguments,
                executable: executable,
                timeout: 8,
                allowNonZeroExit: true
            )
            if startResult.exitCode == 0,
               !containsLaunchFailure(startResult.combinedOutput),
               try await waitForAppForeground(identifier: identifier, deviceID: deviceID, executable: executable) {
                return startResult
            }
        }

        throw CommandRunnerError.nonZeroExit(
            executable: "adb launch \(identifier)",
            exitCode: packageStartResult.exitCode == 0 ? 1 : packageStartResult.exitCode,
            output: packageStartResult.combinedOutput + "\nApp did not become foreground."
        )
    }

    private static func resolveLauncherActivity(identifier: String, deviceID: String?, executable: String) async throws -> String? {
        var arguments: [String] = []
        if let deviceID {
            arguments.append(contentsOf: ["-s", deviceID])
        }
        arguments.append(contentsOf: [
            "shell",
            "cmd",
            "package",
            "resolve-activity",
            "--brief",
            "-c", "android.intent.category.LAUNCHER",
            identifier
        ])

        let result = try await runADB(
            arguments: arguments,
            executable: executable,
            timeout: 6,
            allowNonZeroExit: true
        )

        guard result.exitCode == 0 else { return nil }
        let lines = result.combinedOutput
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.reversed().first(where: { $0.contains("/") })
    }

    private static func containsLaunchFailure(_ output: String) -> Bool {
        let lowered = output.lowercased()
        return lowered.contains("error:")
            || lowered.contains("exception")
            || lowered.contains("does not exist")
            || lowered.contains("unable to resolve")
            || lowered.contains("no activities found")
            || lowered.contains("aborted")
    }

    private static func waitForAppForeground(identifier: String, deviceID: String?, executable: String) async throws -> Bool {
        for attempt in 1...10 {
            try Task.checkCancellation()
            if try await isAppInForeground(identifier: identifier, deviceID: deviceID, executable: executable) {
                return true
            }
            if attempt < 10 {
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        return false
    }

    private static func isAppInForeground(identifier: String, deviceID: String?, executable: String) async throws -> Bool {
        var arguments: [String] = []
        if let deviceID {
            arguments.append(contentsOf: ["-s", deviceID])
        }
        arguments.append(contentsOf: ["shell", "dumpsys", "activity", "activities"])

        let result = try await runADB(
            arguments: arguments,
            executable: executable,
            timeout: 6,
            allowNonZeroExit: true
        )
        guard result.exitCode == 0 else { return false }

        let lowerIdentifier = identifier.lowercased()
        for rawLine in result.combinedOutput.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowered = line.lowercased()
            guard lowered.contains("topresumedactivity") || lowered.contains("resumedactivity") else { continue }
            if lowered.contains("\(lowerIdentifier)/") {
                return true
            }
        }

        // Fallback for older Android dumpsys formats.
        var windowArguments: [String] = []
        if let deviceID {
            windowArguments.append(contentsOf: ["-s", deviceID])
        }
        windowArguments.append(contentsOf: ["shell", "dumpsys", "window", "windows"])
        let windowResult = try await runADB(
            arguments: windowArguments,
            executable: executable,
            timeout: 6,
            allowNonZeroExit: true
        )
        guard windowResult.exitCode == 0 else { return false }
        for rawLine in windowResult.combinedOutput.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowered = line.lowercased()
            guard lowered.contains("mcurrentfocus") || lowered.contains("mfocusedapp") else { continue }
            if lowered.contains("\(lowerIdentifier)/") {
                return true
            }
        }

        return false
    }

    private static func installedPackagePaths(deviceID: String?, executable: String) async throws -> [String: String] {
        var arguments: [String] = []
        if let deviceID {
            arguments.append(contentsOf: ["-s", deviceID])
        }
        arguments.append(contentsOf: ["shell", "pm", "list", "packages", "-f"])
        let result = try await runADB(arguments: arguments, executable: executable, timeout: 30)
        return parseInstalledPackagePaths(result.stdout)
    }

    private static func parseInstalledPackagePaths(_ output: String) -> [String: String] {
        var packageMap: [String: String] = [:]
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("package:") else { continue }
            let payload = line.dropFirst("package:".count)
            guard let eqIndex = payload.lastIndex(of: "=") else { continue }
            let apkPath = String(payload[..<eqIndex])
            let packageID = String(payload[payload.index(after: eqIndex)...])
            guard !packageID.isEmpty else { continue }
            packageMap[packageID] = apkPath
        }
        return packageMap
    }

    private static func detectChangedPackageIdentifier(before: [String: String], after: [String: String]) -> String? {
        let added = after.keys.filter { before[$0] == nil }
        let changedPath = after.keys.filter { key in
            guard let oldPath = before[key], let newPath = after[key] else { return false }
            return oldPath != newPath
        }

        let candidates = added + changedPath
        if candidates.count == 1 {
            return candidates[0]
        }

        if let appCandidate = candidates.first(where: { !($0.hasPrefix("com.android.") || $0.hasPrefix("android.")) }) {
            return appCandidate
        }

        return candidates.first
    }

    private static func adbExecutablePath() async throws -> String {
        let environment = runtimeEnvironment()

        if let override = environment["APKINSTALLER_ADB_PATH_OVERRIDE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty,
           await isUsableADBExecutable(atPath: override, environment: environment) {
            return override
        }

        if let saved = StorageManager.loadADBPath() {
            if await isUsableADBExecutable(atPath: saved, environment: environment) {
                return saved
            }

            // Stale overrides should not block automatic recovery.
            if saved.contains("/") {
                StorageManager.clearADBPath()
            }
        }

        let detection = await detectADBPathWithReport()
        if let detected = detection.resolvedPath {
            StorageManager.saveADBPath(detected)
            return detected
        }

        throw NSError(
            domain: "ADBService",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "ADB executable not found. Configure it in Settings.",
                checkedPathsUserInfoKey: detection.checkedPaths
            ]
        )
    }

    private static func runADB(
        arguments: [String],
        executable: String,
        timeout: TimeInterval,
        allowNonZeroExit: Bool = false
    ) async throws -> CommandResult {
        // Core reliability: do not preflight with `adb start-server` because it can hang and
        // block the actual operation. `adb <command>` already starts the daemon if needed.
        return try await runLoggedCommand(
            executable: executable,
            arguments: arguments,
            environment: runtimeEnvironment(),
            timeout: timeout,
            allowNonZeroExit: allowNonZeroExit
        )
    }

    private static func runLoggedCommand(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval,
        allowNonZeroExit: Bool = false
    ) async throws -> CommandResult {
        let commandLabel = ([executable] + arguments).joined(separator: " ")
        let start = Date()
        await activeInstallLogger?.recordCommandStart(command: commandLabel, timeout: timeout)
        do {
            let result = try await CommandRunner.run(
                executable: executable,
                arguments: arguments,
                environment: environment,
                timeout: timeout,
                allowNonZeroExit: allowNonZeroExit
            )
            await activeInstallLogger?.recordCommandResult(
                command: commandLabel,
                duration: Date().timeIntervalSince(start),
                result: result
            )
            return result
        } catch {
            await activeInstallLogger?.recordCommandFailure(
                command: commandLabel,
                duration: Date().timeIntervalSince(start),
                error: error
            )
            throw error
        }
    }

    private static func reportProgress(_ message: String, onProgress: ((String) async -> Void)?) async {
        await onProgress?(message)
        await activeInstallLogger?.recordProgress(message)
    }

    private static func runtimeEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let androidHome = env["ANDROID_HOME"] ?? env["ANDROID_SDK_ROOT"] ?? "\(NSHomeDirectory())/Library/Android/sdk"
        env["ANDROID_HOME"] = androidHome
        env["ANDROID_SDK_ROOT"] = env["ANDROID_SDK_ROOT"] ?? androidHome

        let extraPaths = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            "\(androidHome)/platform-tools",
            "\(androidHome)/tools",
            "\(androidHome)/tools/bin"
        ]

        let existing = env["PATH"] ?? ""
        let combined = (extraPaths + [existing]).joined(separator: ":")
        env["PATH"] = combined
        return env
    }

    private static func buildADBCandidates(environment: [String: String]) -> [String] {
        var paths: [String] = []
        var seen = Set<String>()

        func add(_ path: String?) {
            guard let path else { return }
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            guard !seen.contains(trimmed) else { return }
            seen.insert(trimmed)
            paths.append(trimmed)
        }

        add(StorageManager.loadADBPath())

        let androidHome = environment["ANDROID_HOME"] ?? environment["ANDROID_SDK_ROOT"] ?? "\(NSHomeDirectory())/Library/Android/sdk"
        add("\(androidHome)/platform-tools/adb")
        if let sdkRoot = environment["ANDROID_SDK_ROOT"] {
            add("\(sdkRoot)/platform-tools/adb")
        }
        if let sdkHome = environment["ANDROID_SDK_HOME"] {
            add("\(sdkHome)/platform-tools/adb")
        }

        let pathFolders = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for folder in pathFolders {
            add(URL(fileURLWithPath: folder).appendingPathComponent("adb").path)
        }

        add("/opt/homebrew/bin/adb")
        add("/usr/local/bin/adb")
        add("/usr/bin/adb")
        // Last resort: rely on PATH resolution. Prefer absolute paths so Settings shows a full path.
        add("adb")

        return paths
    }

    private static func isUsableADBExecutable(atPath path: String, environment: [String: String]) async -> Bool {
        let executable: String
        if path.contains("/") {
            let expandedPath = (path as NSString).expandingTildeInPath
            guard FileManager.default.isExecutableFile(atPath: expandedPath) else {
                return false
            }
            executable = expandedPath
        } else {
            executable = path
        }

        do {
            _ = try await runLoggedCommand(
                executable: executable,
                arguments: ["version"],
                environment: environment,
                timeout: 10
            )
            return true
        } catch {
            return false
        }
    }

    private static func detectAAPTPath(environment: [String: String]) -> String {
        let androidHome = environment["ANDROID_HOME"] ?? "\(NSHomeDirectory())/Library/Android/sdk"
        let buildToolsDir = URL(fileURLWithPath: androidHome).appendingPathComponent("build-tools")

        if let versions = try? FileManager.default.contentsOfDirectory(atPath: buildToolsDir.path).sorted(by: >) {
            for version in versions {
                let candidate = buildToolsDir
                    .appendingPathComponent(version)
                    .appendingPathComponent("aapt")
                    .path
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        return "aapt"
    }

    private static func detectAAPT2Path(environment: [String: String]) -> String? {
        let androidHome = environment["ANDROID_HOME"] ?? "\(NSHomeDirectory())/Library/Android/sdk"
        let buildToolsDir = URL(fileURLWithPath: androidHome).appendingPathComponent("build-tools")

        if let versions = try? FileManager.default.contentsOfDirectory(atPath: buildToolsDir.path).sorted(by: >) {
            for version in versions {
                let candidate = buildToolsDir
                    .appendingPathComponent(version)
                    .appendingPathComponent("aapt2")
                    .path
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        if let fromPath = CommandRunner.findExecutable(named: "aapt2", environment: environment) {
            return fromPath
        }

        return nil
    }

    private static func detectApkAnalyzerPath(environment: [String: String]) -> String? {
        if let fromPath = CommandRunner.findExecutable(named: "apkanalyzer", environment: environment) {
            return fromPath
        }

        let androidHome = environment["ANDROID_HOME"] ?? "\(NSHomeDirectory())/Library/Android/sdk"
        let candidates = [
            "\(androidHome)/cmdline-tools/latest/bin/apkanalyzer",
            "\(androidHome)/cmdline-tools/bin/apkanalyzer",
            "\(androidHome)/tools/bin/apkanalyzer"
        ]

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        return nil
    }

    private static func packageIdentifierUsingAAPT2(
        apkPath: String,
        executable: String,
        environment: [String: String]
    ) async throws -> String {
        let result = try await runLoggedCommand(
            executable: executable,
            arguments: ["dump", "badging", apkPath],
            environment: environment,
            timeout: 15
        )
        return try parsePackageIdentifierFromBadging(result.stdout)
    }

    private static func runADBWithTransientDeviceRetry(
        arguments: [String],
        executable: String,
        timeout: TimeInterval,
        allowNonZeroExit: Bool = false
    ) async throws -> CommandResult {
        var lastResult: CommandResult?

        for attempt in 1...3 {
            let result = try await runADB(
                arguments: arguments,
                executable: executable,
                timeout: timeout,
                allowNonZeroExit: true
            )
            lastResult = result

            if result.exitCode == 0 {
                return result
            }

            let lowered = result.combinedOutput.lowercased()
            let shouldRetry = isTransientDeviceError(output: lowered)
            if !shouldRetry || attempt == 3 {
                if allowNonZeroExit {
                    return result
                }
                throw CommandRunnerError.nonZeroExit(
                    executable: ([executable] + arguments).joined(separator: " "),
                    exitCode: result.exitCode,
                    output: result.combinedOutput
                )
            }

            _ = try? await runADB(
                arguments: ["reconnect", "offline"],
                executable: executable,
                timeout: 6,
                allowNonZeroExit: true
            )
            try await Task.sleep(nanoseconds: 700_000_000)
        }

        if let lastResult {
            if allowNonZeroExit {
                return lastResult
            }
            throw CommandRunnerError.nonZeroExit(
                executable: ([executable] + arguments).joined(separator: " "),
                exitCode: lastResult.exitCode,
                output: lastResult.combinedOutput
            )
        }

        return try await runADB(
            arguments: arguments,
            executable: executable,
            timeout: timeout,
            allowNonZeroExit: allowNonZeroExit
        )
    }

    private static func isTransientDeviceError(output: String) -> Bool {
        output.contains("device offline")
            || output.contains("device '")
            || output.contains("no devices/emulators found")
            || output.contains("waiting for device")
            || output.contains("closed")
            || output.contains("failed to get feature set")
            || output.contains("cannot connect to daemon")
    }

    private static func normalizedFallbackPackageIdentifier(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed != AppConfig.defaultAppIdentifier else { return nil }
        return trimmed
    }

    private static func isCommandCancellation(_ error: Error) -> Bool {
        if case CommandRunnerError.cancelled = error {
            return true
        }
        return false
    }

    private static func attachInstallLogPath(_ error: Error, logPath: String) -> Error {
        let nsError = error as NSError
        var userInfo = nsError.userInfo
        userInfo[installLogPathUserInfoKey] = logPath

        if userInfo[NSLocalizedDescriptionKey] == nil {
            userInfo[NSLocalizedDescriptionKey] = nsError.localizedDescription
        }

        if userInfo[NSUnderlyingErrorKey] == nil {
            userInfo[NSUnderlyingErrorKey] = nsError
        }

        return NSError(
            domain: nsError.domain,
            code: nsError.code,
            userInfo: userInfo
        )
    }

    private static func contextualizedInstallError(_ error: Error, stage: String) -> Error {
        if let commandError = error as? CommandRunnerError {
            switch commandError {
            case .timedOut(_, let timeout):
                return NSError(
                    domain: "ADBService",
                    code: 5,
                    userInfo: [
                        NSLocalizedDescriptionKey: "\(stage) timed out after \(Int(timeout))s. Check ADB connection and selected device state."
                    ]
                )
            case .nonZeroExit(let executable, let exitCode, let output):
                let snippet = output
                    .split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first(where: { !$0.isEmpty }) ?? "No additional output"
                return NSError(
                    domain: "ADBService",
                    code: 6,
                    userInfo: [
                        NSLocalizedDescriptionKey: "\(stage) failed (\(executable), exit \(exitCode)): \(snippet)"
                    ]
                )
            case .executableNotFound, .cancelled:
                return error
            }
        }

        return NSError(
            domain: "ADBService",
            code: 7,
            userInfo: [
                NSLocalizedDescriptionKey: "\(stage) failed: \(error.localizedDescription)"
            ]
        )
    }

    private static func packageResolutionFailure(error: Error, apkPath: String) -> NSError {
        let apkName = URL(fileURLWithPath: apkPath).lastPathComponent

        if let commandError = error as? CommandRunnerError {
            switch commandError {
            case .nonZeroExit(_, _, let output):
                let lowered = output.lowercased()
                if lowered.contains("no androidmanifest.xml found") || lowered.contains("error opening archive") || lowered.contains("invalid file") {
                    return NSError(
                        domain: "ADBService",
                        code: 8,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Could not resolve package ID from \(apkName): APK appears invalid or corrupted (missing AndroidManifest). Re-download the APK."
                        ]
                    )
                }
                if lowered.contains("unable to locate a java runtime") {
                    return NSError(
                        domain: "ADBService",
                        code: 9,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Could not resolve package ID from \(apkName): Java runtime not found for APK analyzer fallback."
                        ]
                    )
                }
            case .executableNotFound:
                return NSError(
                    domain: "ADBService",
                    code: 10,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Could not resolve package ID from \(apkName): Android build-tools not found (aapt/aapt2)."
                    ]
                )
            case .timedOut, .cancelled:
                break
            }
        }

        return NSError(
            domain: "ADBService",
            code: 11,
            userInfo: [
                NSLocalizedDescriptionKey: "Could not resolve package ID from \(apkName): \(error.localizedDescription)"
            ]
        )
    }

    static func parseDevicesOutput(_ output: String) -> [ADBDevice] {
        var devices: [ADBDevice] = []

        for line in output.split(separator: "\n").map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("List of devices attached") {
                continue
            }

            let columns = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard columns.count >= 2 else { continue }

            let id = columns[0]
            let status = ADBDevice.Status(rawValue: columns[1]) ?? .unknown
            var product: String?
            var model: String?
            var deviceCodename: String?
            var transport: String?

            for token in columns.dropFirst(2) {
                let pieces = token.split(separator: ":", maxSplits: 1).map(String.init)
                guard pieces.count == 2 else { continue }

                switch pieces[0] {
                case "product":
                    product = pieces[1]
                case "model":
                    model = pieces[1]
                case "device":
                    deviceCodename = pieces[1]
                case "transport_id":
                    transport = pieces[1]
                default:
                    break
                }
            }

            devices.append(
                ADBDevice(
                    id: id,
                    status: status,
                    product: product,
                    model: model,
                    device: deviceCodename,
                    transportId: transport
                )
            )
        }

        return devices
    }

    static func parsePackageIdentifierFromBadging(_ output: String) throws -> String {
        for line in output.split(separator: "\n") {
            guard line.hasPrefix("package:") else { continue }
            for token in line.split(separator: " ") where token.hasPrefix("name=") {
                return token
                    .replacingOccurrences(of: "name=", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }

        throw NSError(
            domain: "ADBService",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Could not parse package identifier from APK metadata."]
        )
    }

    static func parseADBVersionOutput(_ output: String) -> String {
        for line in output.split(separator: "\n").map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("Android Debug Bridge version") {
                return trimmed
            }
        }

        return output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "ADB available"
    }
}
