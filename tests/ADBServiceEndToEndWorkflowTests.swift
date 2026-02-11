import XCTest
@testable import APKInstaller

final class ADBServiceEndToEndWorkflowTests: XCTestCase {
    func testUpdateFlowUsesReplaceFlagAndSkipsUninstall() async throws {
        let script = """
        #!/bin/zsh
        set -euo pipefail

        if [[ -n "${ADB_LOG_FILE:-}" ]]; then
          printf "%s\\n" "$*" >> "$ADB_LOG_FILE"
        fi

        if [[ "$1" == "-s" ]]; then
          shift 2
        fi

        case "$1" in
          version)
            echo "Android Debug Bridge version 1.0.41"
            ;;
          install)
            echo "Success"
            ;;
          shell)
            echo "Success"
            ;;
          *)
            echo "Unsupported command: $*" >&2
            exit 1
            ;;
        esac
        """

        try await withFakeADB(script: script) { logFile, _ in
            _ = try await ADBService.installAPK(
                path: "/tmp/Update.apk",
                isUpdate: true,
                deviceID: nil,
                fallbackPackageIdentifier: "com.example.update"
            )

            let log = try String(contentsOf: logFile)
            XCTAssertTrue(log.contains("install -t -r /tmp/Update.apk"))
            XCTAssertFalse(log.contains("uninstall com.example.update"))
        }
    }

    func testInstallRetriesTransientOfflineDeviceAndReconnects() async throws {
        let script = """
        #!/bin/zsh
        set -euo pipefail

        if [[ -n "${ADB_LOG_FILE:-}" ]]; then
          printf "%s\\n" "$*" >> "$ADB_LOG_FILE"
        fi

        if [[ "$1" == "-s" ]]; then
          shift 2
        fi

        STATE_FILE="${ADB_STATE_FILE}"
        case "$1" in
          version)
            echo "Android Debug Bridge version 1.0.41"
            ;;
          reconnect)
            echo "reconnected"
            ;;
          install)
            if [[ ! -f "$STATE_FILE" ]]; then
              touch "$STATE_FILE"
              echo "error: device offline" >&2
              exit 1
            fi
            echo "Success"
            ;;
          shell)
            echo "Success"
            ;;
          *)
            echo "Unsupported command: $*" >&2
            exit 1
            ;;
        esac
        """

        try await withFakeADB(script: script) { logFile, tempDir in
            let stateFile = tempDir.appendingPathComponent("adb_state")
            setenv("ADB_STATE_FILE", stateFile.path, 1)
            defer { unsetenv("ADB_STATE_FILE") }

            _ = try await ADBService.installAPK(
                path: "/tmp/Retry.apk",
                isUpdate: true,
                deviceID: nil,
                fallbackPackageIdentifier: "com.example.retry"
            )

            let log = try String(contentsOf: logFile)
            let installAttemptCount = log.components(separatedBy: "install -t -r /tmp/Retry.apk").count - 1
            XCTAssertGreaterThanOrEqual(installAttemptCount, 2)
            XCTAssertTrue(log.contains("reconnect offline"))
        }
    }

    func testInstallReportsLogPathAndOutcome() async throws {
        let script = """
        #!/bin/zsh
        set -euo pipefail

        if [[ -n "${ADB_LOG_FILE:-}" ]]; then
          printf "%s\\n" "$*" >> "$ADB_LOG_FILE"
        fi

        if [[ "$1" == "-s" ]]; then
          shift 2
        fi

        case "$1" in
          version)
            echo "Android Debug Bridge version 1.0.41"
            ;;
          install)
            echo "Success"
            ;;
          shell)
            echo "Success"
            ;;
          *)
            echo "Unsupported command: $*" >&2
            exit 1
            ;;
        esac
        """

        try await withFakeADB(script: script) { _, _ in
            var callbackPath: String?
            let result = try await ADBService.installAPK(
                path: "/tmp/Logged.apk",
                isUpdate: false,
                deviceID: nil,
                fallbackPackageIdentifier: "com.example.logged",
                onLogReady: { path in callbackPath = path }
            )

            XCTAssertNotNil(result.installLogPath)
            XCTAssertEqual(result.installLogPath, callbackPath)

            guard let installLogPath = result.installLogPath else {
                XCTFail("Missing install log path")
                return
            }

            let logContents = try String(contentsOfFile: installLogPath)
            XCTAssertTrue(logContents.contains("CMD START"))
            XCTAssertTrue(logContents.contains("SESSION SUCCESS"))
        }
    }

    func testUpdateUsesSelectedDeviceSerial() async throws {
        let script = """
        #!/bin/zsh
        set -euo pipefail

        if [[ -n "${ADB_LOG_FILE:-}" ]]; then
          printf "%s\\n" "$*" >> "$ADB_LOG_FILE"
        fi

        if [[ "$1" == "-s" ]]; then
          shift 2
        fi

        case "$1" in
          version)
            echo "Android Debug Bridge version 1.0.41"
            ;;
          install)
            echo "Success"
            ;;
          shell)
            echo "Success"
            ;;
          *)
            echo "Unsupported command: $*" >&2
            exit 1
            ;;
        esac
        """

        try await withFakeADB(script: script) { logFile, _ in
            _ = try await ADBService.installAPK(
                path: "/tmp/Selected.apk",
                isUpdate: true,
                deviceID: "emulator-5556",
                fallbackPackageIdentifier: "com.example.selected"
            )

            let log = try String(contentsOf: logFile)
            XCTAssertTrue(log.contains("-s emulator-5556 install -t -r /tmp/Selected.apk"))
        }
    }

    private func withFakeADB(
        script: String,
        body: @escaping (_ logFile: URL, _ tempDir: URL) async throws -> Void
    ) async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let adbFile = tempDir.appendingPathComponent("adb")
        let logFile = tempDir.appendingPathComponent("adb.log")
        try script.write(to: adbFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: adbFile.path)

        let keys = [
            "ADB_LOG_FILE",
            "APKINSTALLER_ADB_PATH_OVERRIDE",
            "APKINSTALLER_SKIP_POST_INSTALL_LAUNCH",
            "ANDROID_HOME",
            "ANDROID_SDK_ROOT"
        ]

        var previous: [String: String] = [:]
        for key in keys {
            if let value = getenv(key) {
                previous[key] = String(cString: value)
            }
        }

        setenv("ADB_LOG_FILE", logFile.path, 1)
        setenv("APKINSTALLER_ADB_PATH_OVERRIDE", adbFile.path, 1)
        setenv("APKINSTALLER_SKIP_POST_INSTALL_LAUNCH", "1", 1)
        setenv("ANDROID_HOME", tempDir.path, 1)
        setenv("ANDROID_SDK_ROOT", tempDir.path, 1)

        defer {
            for key in keys {
                if let original = previous[key] {
                    setenv(key, original, 1)
                } else {
                    unsetenv(key)
                }
            }
            try? FileManager.default.removeItem(at: tempDir)
        }

        try await body(logFile, tempDir)
    }
}
