import XCTest
@testable import APKInstaller

final class ADBServiceIntegrationSmokeTests: XCTestCase {
    func testADBServiceSmokeWithFakeADB() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            unsetenv("ADB_LOG_FILE")
            unsetenv("APKINSTALLER_ADB_PATH_OVERRIDE")
            try? FileManager.default.removeItem(at: tempDir)
        }

        let logFile = tempDir.appendingPathComponent("adb.log")
        let adbFile = tempDir.appendingPathComponent("adb")

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
            cat <<'OUT'
        Android Debug Bridge version 1.0.41
        Version 36.0.0-test
        OUT
            ;;
          devices)
            cat <<'OUT'
        List of devices attached
        emulator-5554 device product:sdk model:Pixel device:emu transport_id:1
        OUT
            ;;
          install)
            echo "Success"
            ;;
          uninstall)
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

        try script.write(to: adbFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: adbFile.path)

        setenv("ADB_LOG_FILE", logFile.path, 1)
        setenv("APKINSTALLER_ADB_PATH_OVERRIDE", adbFile.path, 1)

        let devices = try await ADBService.listDevices()
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices.first?.id, "emulator-5554")

        try await ADBService.installAPK(
            path: "/tmp/My App.apk",
            isUpdate: false,
            deviceID: nil,
            fallbackPackageIdentifier: "com.example.test"
        )

        try await ADBService.clearAppData(identifier: "com.example.test", deviceID: nil)

        let log = try String(contentsOf: logFile)
        XCTAssertTrue(log.contains("devices -l"))
        XCTAssertTrue(log.contains("uninstall com.example.test"))
        XCTAssertTrue(log.contains("install -t /tmp/My App.apk"))
        XCTAssertTrue(log.contains("shell pm clear com.example.test"))
    }

    func testInstallRetriesUntilDeviceBecomesReady() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            unsetenv("ADB_STATE_COUNTER_FILE")
            unsetenv("APKINSTALLER_ADB_PATH_OVERRIDE")
            try? FileManager.default.removeItem(at: tempDir)
        }

        let counterFile = tempDir.appendingPathComponent("state.counter")
        let adbFile = tempDir.appendingPathComponent("adb")

        let script = """
        #!/bin/zsh
        set -euo pipefail

        if [[ "$1" == "-s" ]]; then
          shift 2
        fi

        case "$1" in
          version)
            cat <<'OUT'
        Android Debug Bridge version 1.0.41
        Version 36.0.0-test
        OUT
            ;;
          get-state)
            counter_file="${ADB_STATE_COUNTER_FILE:-}"
            count=0
            if [[ -n "$counter_file" && -f "$counter_file" ]]; then
              count=$(cat "$counter_file")
            fi
            count=$((count + 1))
            if [[ -n "$counter_file" ]]; then
              echo "$count" > "$counter_file"
            fi
            if (( count < 3 )); then
              echo "offline"
            else
              echo "device"
            fi
            ;;
          devices)
            cat <<'OUT'
        List of devices attached
        emulator-5554 device product:sdk model:Pixel device:emu transport_id:1
        OUT
            ;;
          reconnect)
            echo "reconnected"
            ;;
          install)
            echo "Success"
            ;;
          uninstall)
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

        try script.write(to: adbFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: adbFile.path)

        setenv("ADB_STATE_COUNTER_FILE", counterFile.path, 1)
        setenv("APKINSTALLER_ADB_PATH_OVERRIDE", adbFile.path, 1)

        _ = try await ADBService.installAPK(
            path: "/tmp/My App.apk",
            isUpdate: false,
            deviceID: "emulator-5554",
            fallbackPackageIdentifier: "com.example.test"
        )

        let attempts = Int((try? String(contentsOf: counterFile).trimmingCharacters(in: .whitespacesAndNewlines)) ?? "0") ?? 0
        XCTAssertGreaterThanOrEqual(attempts, 3)
    }
}
