import SwiftUI

class ConfigState: ObservableObject {
    @Published var adbPath: String = StorageManager.loadADBPath() ?? ""
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
        // Initialization of other properties happens via defaults or direct assignment
    }
    
    func saveAppIdentifier() {
        StorageManager.saveAppIdentifier(appIdentifier)
    }
} 