import Foundation

enum StorageManager {
    static let adbPathKey = "adb_path"
    static let locationsKey = "saved_apk_locations"
    static let lastSelectedLocationKey = "last_selected_location_path"
    static let bundleSourceKey = "bundle_source_path"
    static let bundleIosDestKey = "bundle_ios_dest_path"
    static let bundleAndroidDestKey = "bundle_android_dest_path"
    static let sourceBookmarkKey = "bundle_source_bookmark"
    static let destBookmarkKey = "bundle_dest_bookmark"
    static let appIdentifierKey = "app_identifier"
    static let deviceSelectorEnabledKey = "device_selector_enabled"
    
    static func saveADBPath(_ path: String) {
        UserDefaults.standard.set(path, forKey: adbPathKey)
    }
    
    static func loadADBPath() -> String? {
        return UserDefaults.standard.string(forKey: adbPathKey)
    }
    
    static func saveAppIdentifier(_ identifier: String) {
        UserDefaults.standard.set(identifier, forKey: appIdentifierKey)
    }

    /// Persist whether manual device selector is enabled.
    static func saveDeviceSelectorEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: deviceSelectorEnabledKey)
    }
    
    static func loadAppIdentifier() -> String {
        return UserDefaults.standard.string(forKey: appIdentifierKey) ?? "com.mpl.androidapp"
    }

    /// Load persisted device selector setting, defaulting to enabled if not set.
    static func loadDeviceSelectorEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: deviceSelectorEnabledKey) != nil {
            return UserDefaults.standard.bool(forKey: deviceSelectorEnabledKey)
        }
        return true
    }
    
    static func saveLocations(_ locations: [APKLocation]) {
        if let encoded = try? JSONEncoder().encode(locations) {
            UserDefaults.standard.set(encoded, forKey: locationsKey)
        }
    }
    
    static func loadLocations() -> [APKLocation] {
        if let data = UserDefaults.standard.data(forKey: locationsKey),
           let decoded = try? JSONDecoder().decode([APKLocation].self, from: data) {
            return decoded
        }
        return []
    }
    
    static func saveBundlePaths(source: String, iosDest: String, androidDest: String) {
        UserDefaults.standard.set(source, forKey: bundleSourceKey)
        UserDefaults.standard.set(iosDest, forKey: bundleIosDestKey)
        UserDefaults.standard.set(androidDest, forKey: bundleAndroidDestKey)
    }
    
    static func loadBundlePaths() -> (source: String?, iosDest: String?, androidDest: String?) {
        let source = UserDefaults.standard.string(forKey: bundleSourceKey)
        let iosDest = UserDefaults.standard.string(forKey: bundleIosDestKey)
        let androidDest = UserDefaults.standard.string(forKey: bundleAndroidDestKey)
        return (source, iosDest, androidDest)
    }
    
    static func saveBookmark(for url: URL, isSource: Bool) throws {
        let bookmarkKey = isSource ? sourceBookmarkKey : destBookmarkKey
        let data = try url.bookmarkData(options: .withSecurityScope,
                                       includingResourceValuesForKeys: nil,
                                       relativeTo: nil)
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }
    
    static func resolveBookmark(isSource: Bool) -> URL? {
        let bookmarkKey = isSource ? sourceBookmarkKey : destBookmarkKey
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: data,
                             options: .withSecurityScope,
                             relativeTo: nil,
                             bookmarkDataIsStale: &isStale)
            return url
        } catch {
            print("Failed to resolve bookmark: \(error)")
            return nil
        }
    }
    
    static func restoreSecurityScopedAccess(for url: URL) -> Bool {
        let success = url.startAccessingSecurityScopedResource()
        if !success {
            print("⚠️ Failed to access security-scoped resource: \(url.path)")
        }
        return success
    }
    
    static func saveLastSelectedLocation(_ location: APKLocation?) {
        if let path = location?.path {
            UserDefaults.standard.set(path, forKey: lastSelectedLocationKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastSelectedLocationKey)
        }
    }
    
    static func loadLastSelectedLocation() -> String? {
        return UserDefaults.standard.string(forKey: lastSelectedLocationKey)
    }
} 