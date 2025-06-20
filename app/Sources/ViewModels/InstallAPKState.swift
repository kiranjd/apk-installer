import SwiftUI

class InstallAPKState: ObservableObject {
    @Published var selectedLocation: APKLocation?
    @Published var apkFiles: [APKFile] = []
    @Published var isScanning = false
    @Published var currentScanPath: String = ""
    @Published var scanError: String?
    @Published var displayLimit = 10
    @Published var hasPermission = false
    
    // Track the current scan task to prevent race conditions
    private var currentScanTask: Task<Void, Never>?
    
    func cancelCurrentScan() {
        currentScanTask?.cancel()
        currentScanTask = nil
        isScanning = false
    }
    
    func setScanTask(_ task: Task<Void, Never>) {
        currentScanTask = task
    }
} 