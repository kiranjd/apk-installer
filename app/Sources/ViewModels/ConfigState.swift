import SwiftUI

class ConfigState: ObservableObject {
    @Published var adbPath: String = StorageManager.loadADBPath() ?? "" {
        didSet {
            StorageManager.saveADBPath(adbPath)
        }
    }
    @Published var appIdentifier: String = StorageManager.loadAppIdentifier()
    @Published var showingADBPicker = false
    /// Whether manual device selector is enabled (show device dropdown).
    @Published var deviceSelectorEnabled: Bool = StorageManager.loadDeviceSelectorEnabled() {
        didSet {
            StorageManager.saveDeviceSelectorEnabled(deviceSelectorEnabled)
        }
    }
    weak var appState: AppState?
    
    init() {
        // Defer ADB path detection to runtime (e.g., when opening Config or listing devices).
    }

    /// Attempts to locate adb via `which adb` and returns its path if found.
    private static func detectADBPath() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["adb"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                return path
            }
        } catch {
            print("⚠️ Failed to detect adb path: \(error.localizedDescription)")
        }
        return nil
    }
    
    func saveAppIdentifier() {
        StorageManager.saveAppIdentifier(appIdentifier)
    }
} 