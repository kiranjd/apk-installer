import SwiftUI

class InstallAPKState: ObservableObject {
    @Published var selectedLocation: APKLocation?
    @Published var apkFiles: [APKFile] = []
    @Published var isScanning = false
    @Published var currentScanPath: String = ""
    @Published var scanError: String?
    @Published var displayLimit = 10
    @Published var hasPermission = false
} 