import SwiftUI
import Combine

@MainActor
final class ADBDeviceState: ObservableObject {
    @Published private(set) var devices: [ADBDevice] = []
    @Published var selectedDeviceID: String?
    @Published var errorMessage: String?
    @Published private(set) var checkedADBPaths: [String] = []
    @Published var lastUpdated: Date?

    private var timerCancellable: AnyCancellable?
    private var fetchTask: Task<Void, Never>?
    private var isFetching = false
    private let pollInterval: TimeInterval
    private var operationPauseCount = 0
    private var lastPathDetection: Date?
    private let pathDetectionRefreshInterval: TimeInterval = 20

    init(pollInterval: TimeInterval = 5.0) {
        self.pollInterval = pollInterval
        fetchDevices()
        startPolling()
    }

    deinit {
        timerCancellable?.cancel()
        fetchTask?.cancel()
    }

    func fetchDevices() {
        guard !isFetching else { return }
        isFetching = true

        fetchTask = Task {
            defer { isFetching = false }
            do {
                let list = try await ADBService.listDevices()
                guard !Task.isCancelled else { return }

                errorMessage = nil
                checkedADBPaths = []
                devices = list

                let readyDevices = list.filter { $0.status == .device }
                if let selectedDeviceID,
                   readyDevices.contains(where: { $0.id == selectedDeviceID }) {
                    // Keep current selection while it remains fully connected.
                } else {
                    // Default to the first connected device/emulator.
                    self.selectedDeviceID = readyDevices.first?.id
                }
                lastUpdated = Date()
            } catch {
                guard !Task.isCancelled else { return }
                if shouldRefreshCheckedPaths(for: error) {
                    let report = await ADBService.detectADBPathWithReport()
                    checkedADBPaths = report.checkedPaths
                    lastPathDetection = Date()
                }

                let nsError = error as NSError
                if let reportedCheckedPaths = nsError.userInfo[ADBService.checkedPathsUserInfoKey] as? [String],
                   !reportedCheckedPaths.isEmpty {
                    checkedADBPaths = reportedCheckedPaths
                }

                errorMessage = friendlyErrorMessage(error)
                devices = []
                selectedDeviceID = nil
                lastUpdated = Date()
            }
        }
    }

    func suspendPollingForOperation() {
        operationPauseCount += 1
        guard operationPauseCount == 1 else { return }
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    func resumePollingAfterOperation() {
        guard operationPauseCount > 0 else { return }
        operationPauseCount -= 1
        guard operationPauseCount == 0 else { return }
        startPolling()
        fetchDevices()
    }

    private func shouldRefreshCheckedPaths(for error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == "ADBService", nsError.code == 1 else {
            return false
        }

        guard let lastPathDetection else { return true }
        return Date().timeIntervalSince(lastPathDetection) >= pathDetectionRefreshInterval
    }

    private func friendlyErrorMessage(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == "ADBService", nsError.code == 1 {
            return "ADB not detected. Open Settings to detect or select adb."
        }
        return error.localizedDescription
    }

    private func startPolling() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: pollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchDevices()
            }
    }
}
