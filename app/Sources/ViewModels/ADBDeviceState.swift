import SwiftUI
import Combine

/// View model for tracking connected Android devices via ADB.
public class ADBDeviceState: ObservableObject {
    /// Latest discovered devices.
    @Published public private(set) var devices: [ADBDevice] = []
    /// Selected device identifier.
    @Published public var selectedDeviceID: String?
    /// Optional error message when listing devices fails.
    @Published public var errorMessage: String?
    /// Timestamp of the last update.
    @Published public var lastUpdated: Date?

    private var timerCancellable: AnyCancellable?

    /// Initializes the state and begins polling for devices.
    /// - Parameter pollInterval: Interval in seconds between device list refreshes.
    public init(pollInterval: TimeInterval = 3.0) {
        fetchDevices()
        timerCancellable = Timer.publish(every: pollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchDevices()
            }
    }

    deinit {
        timerCancellable?.cancel()
    }

    /// Fetches connected devices via ADB and updates published properties.
    public func fetchDevices() {
        Task {
            do {
                let list = try await ADBDeviceService.listDevices()
                await MainActor.run {
                    self.errorMessage = nil
                    self.devices = list
                    // Ensure the selected device is valid, else pick the first connected.
                    if let current = selectedDeviceID,
                       list.contains(where: { $0.id == current }) {
                        // keep current selection
                    } else {
                        self.selectedDeviceID = list.first(where: { $0.status == .device })?.id
                    }
                    self.lastUpdated = Date()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.devices = []
                    self.selectedDeviceID = nil
                    self.lastUpdated = Date()
                }
            }
        }
    }
}