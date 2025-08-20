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
    @EnvironmentObject var configState: ConfigState
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
            
            // Device connection guidance
            if configState.deviceSelectorEnabled && deviceState.devices.isEmpty {
                DeviceConnectionGuidanceView()
            }
            
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

    private struct DeviceConnectionGuidanceView: View {
        var body: some View {
            HStack(spacing: ViewConstants.secondarySpacing) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 16))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("No Android device connected")
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("Please connect an Android device via USB and enable ADB debugging to install APKs.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Help") {
                    // Open ADB setup help
                    if let url = URL(string: "https://developer.android.com/studio/command-line/adb#Enabling") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(ViewConstants.secondarySpacing)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: ViewConstants.cornerRadius))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

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
            HStack(alignment: .center, spacing: ViewConstants.secondarySpacing) {
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

                // Manual refresh button; removed auto-reload and change notifications.
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
                        Button {
                            // Refresh device list when clicked
                            deviceState.fetchDevices()
                        } label: {
                            HStack(spacing: ViewConstants.secondarySpacing) {
                                Text("Device")
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("No device connected")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("No Android devices detected. Connect a device via USB or ensure ADB is enabled.\n\nClick to refresh device list.")
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
                if let location = newLocation {
                    state.scanError = nil
                    checkPermission(location.path)
                } else {
                    state.apkFiles = []
                }
                StorageManager.saveLastSelectedLocation(newLocation)
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
                        // Simple loading indicator
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scanning for APK files...")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            
                            // Show the path being scanned
                            if let selectedPath = state.selectedLocation?.path {
                                Text(selectedPath)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        
                        Spacer()
                        
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
        @State private var visibleItems: Set<String> = []
        
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
                        ForEach(Array(state.apkFiles.prefix(state.displayLimit).enumerated()), id: \.element.id) { index, file in
                            APKFileRow(file: file)
                                .disabled(!state.hasPermission)
                                .opacity(visibleItems.contains(file.id.uuidString) ? 1 : 0)
                                .offset(y: visibleItems.contains(file.id.uuidString) ? 0 : 20)
                                .animation(.easeOut(duration: 0.4).delay(Double(index) * 0.1), value: visibleItems)
                        }
                        
                        if state.apkFiles.count > state.displayLimit {
                            Button {
                                state.displayLimit += 10
                                // Animate new items when "Load More" is pressed
                                animateNewItems()
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
                .onChange(of: state.apkFiles) { _ in
                    // Trigger stagger animation when APK files are loaded
                    animateItems()
                }
            }
        }
        
        private func animateItems() {
            visibleItems.removeAll()
            
            let itemsToShow = Array(state.apkFiles.prefix(state.displayLimit))
            for (index, file) in itemsToShow.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.1) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        _ = visibleItems.insert(file.id.uuidString)
                    }
                }
            }
        }
        
        private func animateNewItems() {
            let currentVisibleCount = visibleItems.count
            let newItemsToShow = Array(state.apkFiles.prefix(state.displayLimit))
            
            for (index, file) in newItemsToShow.enumerated() {
                if index >= currentVisibleCount {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(index - currentVisibleCount) * 0.1) {
                        withAnimation(.easeOut(duration: 0.4)) {
                            _ = visibleItems.insert(file.id.uuidString)
                        }
                    }
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
        
        // Cancel any existing scan before starting a new one
        state.cancelCurrentScan()
        
        // Show loading state immediately
        state.isScanning = true
        state.apkFiles = []
        state.displayLimit = 10
        state.scanError = nil
        
        print("\n=== Starting APK Scan ===")
        print("📂 Root directory: \(path)")

        let scanTask = Task.detached { [weak state] in
            do {
                // Check if task was cancelled before we start
                guard !Task.isCancelled else {
                    print("🚫 Scan cancelled before starting for: \(path)")
                    return
                }
                
                // Check/request permission on background thread
                let hasBookmark = FilePermissionManager.shared.hasBookmark(for: path)
                
                if !hasBookmark {
                    try FilePermissionManager.shared.saveBookmark(for: directoryURL)
                }

                guard FilePermissionManager.shared.restoreAccess(for: path) else {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        state?.scanError = "Please reselect the folder to grant access"
                        state?.isScanning = false
                        state?.hasPermission = false
                    }
                    return
                }

                guard !Task.isCancelled else {
                    print("🚫 Scan cancelled after permission check for: \(path)")
                    return
                }

                await MainActor.run {
                    state?.hasPermission = true
                }

                // Do all scanning in background - no UI updates during scan
                let newFiles = FileManager.getAPKFiles(in: directoryURL)

                // Check if task was cancelled before applying results
                guard !Task.isCancelled else {
                    print("🚫 Scan cancelled before applying results for: \(path)")
                    return
                }

                print("\n✅ Scan completed")
                print("📱 APK files found: \(newFiles.count)")

                // Single UI update at the end
                await MainActor.run {
                    // Double-check that we're still supposed to be scanning this path
                    guard state?.selectedLocation?.path == path else {
                        print("🚫 Location changed during scan, discarding results for: \(path)")
                        return
                    }
                    
                    state?.apkFiles = newFiles
                    state?.isScanning = false
                    state?.currentScanPath = ""
                }

            } catch {
                guard !Task.isCancelled else { return }
                print("❌ Error: \(error.localizedDescription)")
                await MainActor.run {
                    // Only update error state if we're still scanning the same path
                    guard state?.selectedLocation?.path == path else { return }
                    
                    state?.scanError = error.localizedDescription
                    state?.isScanning = false
                    state?.currentScanPath = ""
                    state?.hasPermission = false
                }
            }
        }
        
        // Store the task reference so it can be cancelled later
        state.setScanTask(scanTask)
    }

    private func checkPermission(for path: String) {
        // Cancel any existing scan when checking permission for a new path
        state.cancelCurrentScan()
        
        Task.detached { [weak state] in
            // Check permission on background thread
            let hasPermission = FilePermissionManager.shared.restoreAccess(for: path)
            
            await MainActor.run {
                // Only update state if we're still supposed to be checking this path
                guard state?.selectedLocation?.path == path else { return }
                
                state?.hasPermission = hasPermission
                if !hasPermission {
                    print("❗ No permission for: \(path)")
                    state?.scanError = "Permission needed. Please re-select the folder."
                    state?.apkFiles = [] // Clear files if no permission
                    state?.isScanning = false
                } else {
                    print("✅ Permission OK for: \(path)")
                    state?.scanError = nil // Clear error if permission is now granted
                }
            }
            
            // Only scan if we have permission and we're still supposed to be on this path
            if hasPermission {
                await MainActor.run {
                    guard state?.selectedLocation?.path == path else { return }
                    scanDirectory(path)
                }
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

        openPanel.begin { [self] response in
            if response == .OK {
                if let selectedURL = openPanel.url {
                    // Move heavy operations to background thread
                    Task.detached { [self] in
                        do {
                            // Attempt to save bookmark on background thread
                            try FilePermissionManager.shared.saveBookmark(for: selectedURL)
                            let newLocation = APKLocation(path: selectedURL.path)

                            // Update locations in StorageManager on background thread
                            var currentLocations = StorageManager.loadLocations()
                            
                            await MainActor.run {
                                // UI updates on main thread
                                if !currentLocations.contains(where: { $0.path == newLocation.path }) {
                                    currentLocations.append(newLocation)
                                    StorageManager.saveLocations(currentLocations)
                                    print("💾 New location saved: \(newLocation.path)")

                                    // Select the newly added location
                                    self.state.selectedLocation = newLocation
                                } else {
                                    print("⚠️ Location already exists: \(newLocation.path)")
                                    // Optionally select the existing location if needed
                                    self.state.selectedLocation = currentLocations.first { $0.path == newLocation.path }
                                }
                            }

                        } catch {
                            let errorMessage = "Failed to save folder access: \(error.localizedDescription)"
                            print("❌ \(errorMessage)")
                            await MainActor.run {
                                self.statusViewModel.showMessage(errorMessage, type: .error)
                            }
                        }
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
