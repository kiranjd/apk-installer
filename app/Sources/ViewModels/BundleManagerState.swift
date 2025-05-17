import SwiftUI

class BundleManagerState: ObservableObject {
    @Published var selectedPlatform: BundlePlatform = .android
    @Published var sourcePath: String = StorageManager.loadBundlePaths().source ?? ""
    @Published var iosDestPath: String = StorageManager.loadBundlePaths().iosDest ?? ""
    @Published var androidDestPath: String = StorageManager.loadBundlePaths().androidDest ?? ""
    @Published var operationLogs: [String] = []
    @Published var isProcessing = false
    @Published var errorMessage: String?
    @Published var hasSourcePermission = false
    @Published var hasDestPermission = false
    @Published var shouldCreateNewBundle = false
    
    var currentDestPath: String {
        selectedPlatform == .ios ? iosDestPath : androidDestPath
    }
    
    func setDestPath(_ path: String) {
        if selectedPlatform == .ios {
            iosDestPath = path
        } else {
            androidDestPath = path
        }
    }
} 