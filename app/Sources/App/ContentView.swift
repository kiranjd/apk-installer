import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var appState = AppState()
    @EnvironmentObject var statusViewModel: StatusViewModel
    
    @State private var selection: Int? = 0
    @State private var showingPermissionAlert = false
    @State private var permissionAlertMessage = ""
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .detailOnly
    
    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            List(selection: $selection) {
                NavigationLink(value: 0) {
                    Label("Install APK", systemImage: "square.and.arrow.down.fill")
                        .font(.body.weight(.medium))
                }
                NavigationLink(value: 2) {
                    Label("RN to Native", systemImage: "archivebox.fill")
                        .font(.body.weight(.medium))
                }
                NavigationLink(value: 1) {
                    Label("Config", systemImage: "gearshape.2.fill")
                        .font(.body.weight(.medium))
                }
            }
            .navigationTitle("DevTools")
            .frame(width: ViewConstants.sidebarWidth)
        } detail: {
            Group {
                switch selection {
                case 0: InstallAPKView(state: appState.installAPKState, selection: $selection)
                    .environmentObject(appState.configState)
                case 1: ConfigView(state: appState.configState)
                case 2: BundleManagerView(state: appState.bundleManagerState, selection: $selection)
                default: InstallAPKView(state: appState.installAPKState, selection: $selection)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                StatusBarView(viewModel: statusViewModel)
            }
        }
        .alert("Permission Required", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(permissionAlertMessage)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(StatusViewModel())
} 