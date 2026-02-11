import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var installAPKState: InstallAPKState
    @Published var configState: ConfigState
    @Published var deviceState: ADBDeviceState

    init() {
        self.installAPKState = InstallAPKState()
        self.configState = ConfigState()
        self.deviceState = ADBDeviceState()
    }
}
