import Foundation

/// Represents an Android device as reported by `adb devices -l`.
public struct ADBDevice: Identifiable, Equatable {
    public enum Status: String {
        case device, offline, unauthorized, unknown, bootloader, recovery, sideload
    }

    /// Unique device identifier (serial number).
    public let id: String
    /// Connection status (e.g., `device`, `offline`, `unauthorized`).
    public let status: Status
    /// Build product name, if available.
    public let product: String?
    /// Model name, if available.
    public let model: String?
    /// Device codename, if available.
    public let device: String?
    /// Transport ID, if available.
    public let transportId: String?

    /// Readable display name including model and status.
    public var displayName: String {
        var parts = [id]
        if let model = model {
            parts.append("(\(model))")
        }
        if status != .device {
            parts.append("[\(status.rawValue)]")
        }
        return parts.joined(separator: " ")
    }
}

/// Service for listing Android devices via ADB.
public enum ADBDeviceService {
    /// Runs `adb devices -l`, parses the output, and returns device info.
    public static func listDevices() async throws -> [ADBDevice] {
        let adbPath = StorageManager.loadADBPath() ?? "adb"
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = ["devices", "-l"]

        var env = ProcessInfo.processInfo.environment
        let androidHome = env["ANDROID_HOME"] ?? "\(NSHomeDirectory())/Library/Android/sdk"
        env["PATH"] = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            "\(androidHome)/platform-tools",
            "\(androidHome)/tools",
            "\(androidHome)/tools/bin",
            env["PATH"] ?? ""
        ].joined(separator: ":")
        process.environment = env

        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw NSError(domain: "ADBDeviceService",
                          code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: output])
        }

        var devices: [ADBDevice] = []
        for line in output.split(separator: "\n").map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("List of devices attached") {
                continue
            }
            let cols = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard cols.count >= 2 else { continue }
            let id = cols[0]
            let status = ADBDevice.Status(rawValue: cols[1]) ?? .unknown
            var product: String?
            var model: String?
            var deviceCodename: String?
            var transport: String?
            for token in cols.dropFirst(2) {
                let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                switch parts[0] {
                case "product": product = parts[1]
                case "model": model = parts[1]
                case "device": deviceCodename = parts[1]
                case "transport_id": transport = parts[1]
                default: break
                }
            }
            devices.append(ADBDevice(
                id: id,
                status: status,
                product: product,
                model: model,
                device: deviceCodename,
                transportId: transport
            ))
        }
        return devices
    }
}