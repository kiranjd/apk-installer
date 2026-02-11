import SwiftUI

@MainActor
final class ConfigState: ObservableObject {
    @Published var adbPath: String = StorageManager.loadADBPath() ?? "" {
        didSet {
            StorageManager.saveADBPath(adbPath)
        }
    }

    @Published var appIdentifier: String = StorageManager.loadAppIdentifier()
    @Published var showingADBPicker = false

    func saveAppIdentifier() {
        StorageManager.saveAppIdentifier(appIdentifier)
    }
}
