import Foundation

enum StorageManager {
    private static let adbPathKey = "adb_path"
    private static let locationsKey = "saved_apk_locations"
    private static let lastSelectedLocationKey = "last_selected_location_path"
    private static let appIdentifierKey = "app_identifier"
    private static let deviceSelectorEnabledKey = "device_selector_enabled"
    private static let lastInstalledAPKPathKey = "last_installed_apk_path"
    private static let lastInstalledAtKey = "last_installed_at"

    static func saveADBPath(_ path: String) {
        UserDefaults.standard.set(path, forKey: adbPathKey)
    }

    static func loadADBPath() -> String? {
        guard let rawValue = UserDefaults.standard.string(forKey: adbPathKey) else {
            return nil
        }

        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            clearADBPath()
            return nil
        }

        // Keep command-name inputs (e.g. "adb"), but sanitize stale absolute paths.
        if value.contains("/") {
            let expandedPath = (value as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expandedPath) else {
                clearADBPath()
                return nil
            }
            return expandedPath
        }

        return value
    }

    static func clearADBPath() {
        UserDefaults.standard.removeObject(forKey: adbPathKey)
    }

    static func saveAppIdentifier(_ identifier: String) {
        UserDefaults.standard.set(identifier, forKey: appIdentifierKey)
    }

    static func loadAppIdentifier() -> String {
        guard let value = UserDefaults.standard.string(forKey: appIdentifierKey), !value.isEmpty else {
            return AppConfig.defaultAppIdentifier
        }

        // Legacy builds shipped with a personal default package that ended in ".androidapp".
        if value.hasSuffix(".androidapp") {
            return AppConfig.defaultAppIdentifier
        }

        return value
    }

    static func saveDeviceSelectorEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: deviceSelectorEnabledKey)
    }

    static func loadDeviceSelectorEnabled() -> Bool {
        guard UserDefaults.standard.object(forKey: deviceSelectorEnabledKey) != nil else {
            return true
        }
        return UserDefaults.standard.bool(forKey: deviceSelectorEnabledKey)
    }

    static func saveLocations(_ locations: [APKLocation]) {
        guard let encoded = try? JSONEncoder().encode(locations) else { return }
        UserDefaults.standard.set(encoded, forKey: locationsKey)
    }

    static func loadLocations() -> [APKLocation] {
        if let data = UserDefaults.standard.data(forKey: locationsKey),
           let decoded = try? JSONDecoder().decode([APKLocation].self, from: data) {
            return decoded
        }

        // Migration path: older builds (and some local dev workflows) stored an array
        // of folder paths (String) instead of JSON-encoded [APKLocation].
        if let rawPaths = UserDefaults.standard.array(forKey: locationsKey) as? [String] {
            let locations = rawPaths
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { APKLocation(path: $0) }
            if !locations.isEmpty {
                saveLocations(locations)
            }
            return locations
        }

        return []
    }

    static func saveLastSelectedLocation(_ location: APKLocation?) {
        if let path = location?.path {
            UserDefaults.standard.set(path, forKey: lastSelectedLocationKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastSelectedLocationKey)
        }
    }

    static func loadLastSelectedLocation() -> String? {
        UserDefaults.standard.string(forKey: lastSelectedLocationKey)
    }

    static func saveLastInstalledAPKPath(_ path: String?) {
        if let path, !path.isEmpty {
            UserDefaults.standard.set(path, forKey: lastInstalledAPKPathKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastInstalledAPKPathKey)
        }
    }

    static func loadLastInstalledAPKPath() -> String? {
        UserDefaults.standard.string(forKey: lastInstalledAPKPathKey)
    }

    static func saveLastInstalledAt(_ date: Date?) {
        if let date {
            UserDefaults.standard.set(date, forKey: lastInstalledAtKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastInstalledAtKey)
        }
    }

    static func loadLastInstalledAt() -> Date? {
        UserDefaults.standard.object(forKey: lastInstalledAtKey) as? Date
    }

    static func resetAll() {
        clearADBPath()
        UserDefaults.standard.removeObject(forKey: locationsKey)
        UserDefaults.standard.removeObject(forKey: lastSelectedLocationKey)
        UserDefaults.standard.removeObject(forKey: appIdentifierKey)
        UserDefaults.standard.removeObject(forKey: deviceSelectorEnabledKey)
        UserDefaults.standard.removeObject(forKey: lastInstalledAPKPathKey)
        UserDefaults.standard.removeObject(forKey: lastInstalledAtKey)
    }
}
