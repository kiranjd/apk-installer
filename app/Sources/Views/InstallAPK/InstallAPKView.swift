// This is a comment to test for formatting issues.
import SwiftUI
import AppKit
import Combine
import Dispatch

struct InstallAPKView: View {
    @StateObject var state: InstallAPKState
    @Binding var selection: Int?
    @AppStorage("hasDismissedLocationInfo") private var hasDismissedLocationInfo = false
    @EnvironmentObject var statusViewModel: StatusViewModel
    @StateObject private var deviceState = ADBDeviceState()
    
    private func openSecuritySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: ViewConstants.primarySpacing) {
            InfoBarView(hasDismissedLocationInfo: $hasDismissedLocationInfo)
            LocationAndDevicePickerView(state: state, deviceState: deviceState, selectNewLocation: selectNewLocation, checkPermission: checkPermission)
            PermissionStatusSectionView(state: state)
            ScanningStatusView(state: state, openSecuritySettings: openSecuritySettings)
            APKListView(state: state)
        }
        .padding(ViewConstants.primarySpacing)
        .onAppear {
            let locations = StorageManager.loadLocations()
            // Restore last selected location if available, otherwise default to the first.
            if state.selectedLocation == nil {
                if let lastPath = StorageManager.loadLastSelectedLocation(),
                   let lastLocation = locations.first(where: { $0.path == lastPath }) {
                    state.selectedLocation = lastLocation
                } else if !locations.isEmpty {
                    state.selectedLocation = locations[0]
                }
            }
            if let path = state.selectedLocation?.path {
                checkPermission(for: path)
            }
        }
        .environmentObject(deviceState)
    }
    
    // MARK: - Subviews

    private struct InfoBarView: View {
        @Binding var hasDismissedLocationInfo: Bool
        
        var body: some View {
            if !hasDismissedLocationInfo {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    Text("Tip: Use the '+' button next to the dropdown to add new APK locations.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        withAnimation {
                            hasDismissedLocationInfo = true
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(ViewConstants.secondarySpacing)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: ViewConstants.cornerRadius))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private struct LocationAndDevicePickerView: View {
        @ObservedObject var state: InstallAPKState
        @ObservedObject var deviceState: ADBDeviceState
        let selectNewLocation: () -> Void
        let checkPermission: (String) -> Void

        @EnvironmentObject private var statusViewModel: StatusViewModel
        @EnvironmentObject var configState: ConfigState
        @State private var directoryMonitor: DirectoryMonitor?
        
        var body: some View {
            HStack {
                Picker("Location", selection: $state.selectedLocation) {
                    Text("ℹ️ Select or add a location with APKs")
                        .tag(Optional<APKLocation>.none)

                    ForEach(StorageManager.loadLocations()) { location in
                        LocationPickerRowView(location: location)
                            .tag(Optional(location))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 400)

                Button {
                    selectNewLocation()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Add a new folder location")

                // Refresh the APK list for the currently selected folder.
                Button {
                    if let path = state.selectedLocation?.path {
                        state.scanError = nil
                        checkPermission(path)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Refresh APK list")

                if configState.deviceSelectorEnabled {
                    Spacer(minLength: ViewConstants.primarySpacing)
                    // Device menu / status
                    Group {
                    if let error = deviceState.errorMessage {
                        HStack(spacing: ViewConstants.secondarySpacing) {
                            Text("Device")
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                        }
                        .help("Error listing devices")
                    } else if deviceState.devices.isEmpty {
                        HStack(spacing: ViewConstants.secondarySpacing) {
                            Text("Device")
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.secondary)
                            Text("No devices")
                        }
                        .font(.caption)
                        .help("No connected devices")
                    } else {
                        HStack(spacing: ViewConstants.secondarySpacing) {
                            Text("Device")
                            Menu {
                                ForEach(deviceState.devices) { device in
                                    Button {
                                        deviceState.selectedDeviceID = device.id
                                    } label: {
                                        HStack {
                                            Text(device.displayName)
                                            if device.id == deviceState.selectedDeviceID {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: ViewConstants.secondarySpacing) {
                                    Image(systemName: "cpu.fill")
                                    Text(deviceState.devices.first(where: { $0.id == deviceState.selectedDeviceID })?.displayName ?? "Select Device")
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .font(.caption)
                            }
                            .menuStyle(.borderlessButton)
                            .buttonStyle(.plain)
                            .help(deviceState.lastUpdated.map { "Last updated: \($0.formatted(.relative(presentation: .named)))" } ?? "Fetching devices...")
                        }
                    }
                    }
                }
            }
            .onChange(of: state.selectedLocation) { newLocation in
                directoryMonitor?.stop()
                directoryMonitor = nil
                if let location = newLocation {
                    state.scanError = nil
                    checkPermission(location.path)
                    let url = URL(fileURLWithPath: location.path)
                    let monitor = DirectoryMonitor(url: url)
                    monitor.start {
                        DispatchQueue.main.async {
                            statusViewModel.showMessage(
                                "Folder content changed. Reloading APK list...",
                                type: .info
                            )
                            state.scanError = nil
                            checkPermission(location.path)
                        }
                    }
                    directoryMonitor = monitor
                } else {
                    state.apkFiles = []
                }
                StorageManager.saveLastSelectedLocation(newLocation)
            }
            .onDisappear {
                directoryMonitor?.stop()
                directoryMonitor = nil
            }
        }
    }

    private struct PermissionStatusSectionView: View {
        @ObservedObject var state: InstallAPKState
        
        var body: some View {
            if let location = state.selectedLocation {
                PermissionStatusView(path: location.path, hasPermission: state.hasPermission)
                    .padding(.horizontal, ViewConstants.primarySpacing)
            }
        }
    }

    private struct ScanningStatusView: View {
        @ObservedObject var state: InstallAPKState
        let openSecuritySettings: () -> Void
        
        var body: some View {
            if state.isScanning || state.scanError != nil {
                HStack(spacing: ViewConstants.secondarySpacing) {
                    if state.isScanning {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 16, height: 16)
                        Text("Scanning...")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(state.currentScanPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    } else if let error = state.scanError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .foregroundStyle(.red)
                        Spacer()
                        Button("Open Settings") {
                            openSecuritySettings()
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .font(.caption)
                .padding(ViewConstants.secondarySpacing)
                .background {
                    RoundedRectangle(cornerRadius: ViewConstants.cornerRadius)
                        .fill(Color.primary.opacity(0.05))
                }
            }
        }
    }

    private struct APKListView: View {
        @ObservedObject var state: InstallAPKState
        
        var body: some View {
            if state.apkFiles.isEmpty && !state.isScanning {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No APKs Found")
                        .font(.headline)
                    Text("Select or add a folder containing APK files")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // APK Files List
                ScrollView {
                    LazyVStack(spacing: ViewConstants.cardSpacing) {
                        ForEach(state.apkFiles.prefix(state.displayLimit)) { file in
                            APKFileRow(file: file)
                                .disabled(!state.hasPermission)
                        }
                        
                        if state.apkFiles.count > state.displayLimit {
                            Button {
                                state.displayLimit += 10
                            } label: {
                                HStack {
                                    Text("Load More")
                                    Text("(\((state.apkFiles.count - state.displayLimit)) remaining)")
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, ViewConstants.secondarySpacing)
                            }
                            .buttonStyle(.plain)
                            .background {
                                RoundedRectangle(cornerRadius: ViewConstants.cornerRadius)
                                    .fill(Color.primary.opacity(ViewConstants.cardBackgroundOpacity))
                            }
                            .padding(.horizontal, ViewConstants.listPadding)
                        }
                    }
                    .padding(.horizontal, ViewConstants.listPadding)
                }
            }
        }
    }

    // Extracted Row View for Hover State Management
    private struct LocationPickerRowView: View {
        let location: APKLocation

        var body: some View {
            HStack {
                Text(location.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            // Prevent the row selection from triggering the delete button action immediately
            .onTapGesture { /* Absorb tap, Picker handles selection */ }
        }
    }

    private func scanDirectory(_ path: String) {
        let directoryURL = URL(fileURLWithPath: path)
        
        // Check/request permission
        state.hasPermission = FilePermissionManager.shared.hasBookmark(for: path)
        if !state.hasPermission {
            do {
                try FilePermissionManager.shared.saveBookmark(for: directoryURL)
                state.hasPermission = true
            } catch {
                state.scanError = "Failed to get permission: \(error.localizedDescription)"
                return
            }
        }

        guard FilePermissionManager.shared.restoreAccess(for: path) else {
            state.scanError = "Please reselect the folder to grant access"
            return
        }

        state.isScanning = true
        state.apkFiles = []
        state.displayLimit = 10
        print("\n=== Starting APK Scan ===")
        print("📂 Root directory: \(path)")

        Task {
            do {
                let fileManager = Foundation.FileManager.default

                print("\n📝 Directory contents:")
                if let contents = try? fileManager.contentsOfDirectory(atPath: directoryURL.path) {
                    contents.prefix(5).forEach { print("- \($0)") }
                    if contents.count > 5 {
                        print("... and \(contents.count - 5) more files")
                    }
                } else {
                    print("❌ Could not list directory contents")
                }

                let newFiles = FileManager.getAPKFiles(in: directoryURL)

                print("\n✅ Scan completed")
                print("📊 Total files scanned: \(newFiles.count)")
                print("📱 APK files found: \(newFiles.count)")

                await MainActor.run {
                    state.apkFiles = newFiles
                    state.isScanning = false
                    state.currentScanPath = ""
                }

            } catch {
                print("❌ Error: \(error.localizedDescription)")
                await MainActor.run {
                    state.scanError = error.localizedDescription
                    state.isScanning = false
                    state.currentScanPath = ""
                }
            }
        }
    }

    private func checkPermission(for path: String) {
         Task { @MainActor in // Ensure UI updates happen on the main thread
             state.hasPermission = FilePermissionManager.shared.restoreAccess(for: path)
             if !state.hasPermission {
                 print("❗ No permission for: \\(path)")
                 state.scanError = "Permission needed. Please re-select the folder."
                 state.apkFiles = [] // Clear files if no permission
                 state.isScanning = false
             } else {
                 print("✅ Permission OK for: \\(path)")
                 state.scanError = nil // Clear error if permission is now granted
                 scanDirectory(path) // Scan the directory now that we have permission
             }
         }
    }

    private func selectNewLocation() {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.canCreateDirectories = true
        openPanel.prompt = "Select Folder"

        openPanel.begin { response in
            if response == .OK {
                if let selectedURL = openPanel.url {
                    do {
                        // Attempt to save bookmark immediately
                        try FilePermissionManager.shared.saveBookmark(for: selectedURL)
                        let newLocation = APKLocation(path: selectedURL.path)

                        // Update locations in StorageManager
                        var currentLocations = StorageManager.loadLocations()
                        // Avoid adding duplicates
                        if !currentLocations.contains(where: { $0.path == newLocation.path }) {
                            currentLocations.append(newLocation)
                            StorageManager.saveLocations(currentLocations)
                            print("💾 New location saved: \\(newLocation.path)")

                            // Select the newly added location
                            state.selectedLocation = newLocation

                        } else {
                             print("⚠️ Location already exists: \\(newLocation.path)")
                             // Optionally select the existing location if needed
                             state.selectedLocation = currentLocations.first { $0.path == newLocation.path }
                        }

                    } catch {
                        let errorMessage = "Failed to save folder access: \\(error.localizedDescription)"
                        print("❌ \(errorMessage)")
                        statusViewModel.showMessage(errorMessage, type: .error)
                    }
                }
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var selection: Int? = 0
        var body: some View {
             InstallAPKView(state: AppState().installAPKState, selection: $selection)
                 .environmentObject(StatusViewModel())
                 .frame(width: 600, height: 400)
        }
    }
    return PreviewWrapper()
} 
