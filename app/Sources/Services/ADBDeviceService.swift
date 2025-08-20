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
        // Determine how to invoke adb
        var adbInvocation: String
        if let saved = StorageManager.loadADBPath(),
           FileManager.default.isExecutableFile(atPath: saved) {
            adbInvocation = "'\(saved)'"
        } else {
            // Try to auto-detect and persist the adb path using the shell environment
            if let detected = await ShellCommand.detectADBPath() {
                StorageManager.saveADBPath(detected)
                adbInvocation = "'\(detected)'"
            } else {
                // Fall back to PATH and rely on the shell to resolve adb
                adbInvocation = "adb"
            }
        }

        // Run via our shell executor so PATH and ANDROID_HOME are respected
        let output = try await ShellCommand.execute("\(adbInvocation) devices -l")

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