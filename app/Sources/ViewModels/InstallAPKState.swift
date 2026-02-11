import SwiftUI

@MainActor
final class InstallAPKState: ObservableObject {
    @Published var selectedLocation: APKLocation?
    @Published var apkFiles: [APKFile] = []
    @Published var selectedAPKPath: String?
    @Published var isScanning = false
    @Published var scanError: String?
    @Published var displayLimit = 10
    @Published var hasPermission = false
    @Published var lastScanAt: Date?
    @Published var lastInstalledAPKPath: String? {
        didSet { StorageManager.saveLastInstalledAPKPath(lastInstalledAPKPath) }
    }
    @Published var lastInstalledAt: Date? {
        didSet { StorageManager.saveLastInstalledAt(lastInstalledAt) }
    }

    private var currentScanTask: Task<Void, Never>?

    init() {
        self.lastInstalledAPKPath = StorageManager.loadLastInstalledAPKPath()
        self.lastInstalledAt = StorageManager.loadLastInstalledAt()
    }

    func cancelCurrentScan() {
        currentScanTask?.cancel()
        currentScanTask = nil
        isScanning = false
    }

    func setScanTask(_ task: Task<Void, Never>) {
        currentScanTask = task
    }
}
