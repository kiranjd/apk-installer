import SwiftUI
import AppKit

struct InstallAPKView: View {
    @StateObject var state: InstallAPKState
    @Binding var selection: Int?

    @AppStorage("hasDismissedLocationInfo") private var hasDismissedLocationInfo = false
    @EnvironmentObject private var statusViewModel: StatusViewModel
    @EnvironmentObject private var configState: ConfigState
    @EnvironmentObject private var deviceState: ADBDeviceState

    @State private var locations: [APKLocation] = []
    @State private var didAutoPromptForFolderAccess = false

    private let fieldLabelWidth: CGFloat = 64
    private let selectorMinWidth: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: ViewConstants.primarySpacing) {
            Text("APK Installer")
                .font(.system(.title2, design: .rounded).weight(.semibold))
            Text("Install and update APK files on Android devices over ADB.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            infoBar
            folderAndDeviceRow
            deviceConnectionGuidance
            scanningStatus
            apkList
        }
        .padding(ViewConstants.primarySpacing)
        .navigationTitle("Install APK")
        .onAppear {
            reloadLocations()
            restoreInitialSelection()
        }
        .onChange(of: state.selectedLocation) { newLocation in
            guard let newLocation else {
                state.apkFiles = []
                state.selectedAPKPath = nil
                state.hasPermission = false
                return
            }
            StorageManager.saveLastSelectedLocation(newLocation)
            checkPermission(for: newLocation.path)
        }
        .onReceive(NotificationCenter.default.publisher(for: .apkInstallDidSucceed)) { output in
            let installedPath = output.userInfo?["apkPath"] as? String
            state.lastInstalledAPKPath = installedPath
            state.lastInstalledAt = Date()
        }
    }

    // MARK: - UI

    private var infoBar: some View {
        Group {
            if !hasDismissedLocationInfo {
                VStack(alignment: .leading, spacing: 8) {
                    StepChecklistRow(
                        title: "Choose a folder with APK files",
                        isCompleted: isFolderStepCompleted
                    )
                    StepChecklistRow(
                        title: "Connect your Android device or emulator",
                        isCompleted: isDeviceStepCompleted
                    )
                    StepChecklistRow(
                        title: "Install or Update an APK",
                        isCompleted: isInstallStepCompleted
                    )

                    HStack {
                        Spacer()
                        Button("Done") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                hasDismissedLocationInfo = true
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.top, 6)
                }
                .padding(ViewConstants.secondarySpacing)
                .background(Color.blue.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: ViewConstants.cornerRadius))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private struct StepChecklistRow: View {
        let title: String
        let isCompleted: Bool

        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isCompleted ? .green : .blue)
                    .font(.system(size: 15, weight: .semibold))

                Text(title)
                    .font(.callout)
                    .foregroundStyle(isCompleted ? .primary : .secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var folderAndDeviceRow: some View {
        HStack(alignment: .center, spacing: 12) {
            folderGroup
                .frame(maxWidth: .infinity, alignment: .leading)
            deviceGroup
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var folderGroup: some View {
        HStack(spacing: 8) {
            Text("Folder")
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .frame(width: fieldLabelWidth, alignment: .leading)

            Picker("", selection: $state.selectedLocation) {
                Text("Select a folder with APKs…").tag(Optional<APKLocation>.none)
                ForEach(locations) { location in
                    Text(displayPath(location.path)).tag(Optional(location))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: selectorMinWidth, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            ControlGroup {
                Button {
                    chooseFolder()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .help("Add folder")

                Button {
                    refreshFolder()
                } label: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                }
                .help("Refresh APK list")
            }
            .controlGroupStyle(.navigation)
            .fixedSize(horizontal: true, vertical: false)
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var deviceGroup: some View {
        HStack(spacing: 8) {
            Text("Device")
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .frame(width: fieldLabelWidth, alignment: .leading)

            devicePicker
                .frame(minWidth: selectorMinWidth, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            deviceConnectionIndicator

            if shouldShowADBInfoIcon {
                Button {
                    openADBHelp()
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .help("ADB setup help")
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var deviceConnectionGuidance: some View {
        Group {
            if shouldShowConnectionBanner {
                HStack(spacing: ViewConstants.secondarySpacing) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 16))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(unauthorizedDevices.isEmpty ? "No Android device connected" : "Authorize on phone")
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        Text(
                            unauthorizedDevices.isEmpty
                                ? "Connect an Android device via USB and enable USB debugging."
                                : "Unlock your phone and tap “Allow USB debugging”, then refresh devices."
                        )
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        Button("Open USB debugging guide") { openADBHelp() }
                            .buttonStyle(.link)

                        Button("Refresh devices") { deviceState.fetchDevices() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .font(.caption)
                    .fixedSize()
                }
                .overlay(alignment: .trailing) {
                    if !unauthorizedDevices.isEmpty {
                        Text("Authorize on phone")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.18))
                            .clipShape(Capsule())
                            .padding(.trailing, 8)
                            .padding(.top, 6)
                    }
                }
                .padding(ViewConstants.secondarySpacing)
                .background(Color.orange.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: ViewConstants.cornerRadius))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var shouldShowConnectionBanner: Bool {
        readyDevices.isEmpty && deviceState.errorMessage == nil
    }

    private var unauthorizedDevices: [ADBDevice] {
        deviceState.devices.filter { $0.status == .unauthorized }
    }

    private var discoveredDevices: [ADBDevice] {
        deviceState.devices
    }

    private var isFolderStepCompleted: Bool {
        state.selectedLocation != nil && state.hasPermission
    }

    private var isDeviceStepCompleted: Bool {
        !readyDevices.isEmpty
    }

    private var isInstallStepCompleted: Bool {
        state.lastInstalledAt != nil
    }

    private var deviceStatusChip: some View {
        let (text, fg, bg): (String, Color, Color) = {
            if let error = deviceState.errorMessage, !error.isEmpty {
                return ("ADB error", .red, Color.red.opacity(0.14))
            }
            if !unauthorizedDevices.isEmpty {
                return ("Unauthorized", .orange, Color.orange.opacity(0.18))
            }
            if readyDevices.isEmpty {
                return ("Not connected", .orange, Color.orange.opacity(0.16))
            }
            return ("\(readyDevices.count) connected", .green, Color.green.opacity(0.16))
        }()

        return Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(fg)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(bg)
            .clipShape(Capsule())
    }

    private var selectedDeviceTitle: String {
        discoveredDevices.first(where: { $0.id == deviceState.selectedDeviceID })?.displayName ?? "Select Device"
    }

    private var devicePicker: some View {
        Picker("", selection: Binding<String?>(
            get: { deviceState.selectedDeviceID },
            set: { deviceState.selectedDeviceID = $0 }
        )) {
            if discoveredDevices.isEmpty {
                Text("No devices").tag(Optional<String>.none)
            } else {
                ForEach(discoveredDevices) { device in
                    Text(device.displayName).tag(Optional(device.id))
                }
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(minWidth: selectorMinWidth, maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
        .help(deviceState.lastUpdated.map { "Last updated: \($0.formatted(.relative(presentation: .named)))" } ?? "Fetching devices…")
    }

    private var deviceConnectionIndicator: some View {
        let color: Color = {
            if let error = deviceState.errorMessage, !error.isEmpty { return .red }
            if !unauthorizedDevices.isEmpty { return .orange }
            if readyDevices.isEmpty { return .orange }
            return .green
        }()

        let label: String = {
            if let error = deviceState.errorMessage, !error.isEmpty { return "ADB error" }
            if !unauthorizedDevices.isEmpty { return "Device unauthorized" }
            if readyDevices.isEmpty { return "No connected device" }
            return "\(readyDevices.count) connected"
        }()

        return Image(systemName: "circle.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .help(label)
    }

    private var shouldShowADBInfoIcon: Bool {
        if let error = deviceState.errorMessage, !error.isEmpty {
            return true
        }
        return readyDevices.isEmpty || !unauthorizedDevices.isEmpty
    }

    private var scanningStatus: some View {
        Group {
            if state.isScanning || state.scanError != nil {
                HStack(spacing: ViewConstants.secondarySpacing) {
                    if state.isScanning {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scanning for APK files…")
                                .foregroundStyle(.secondary)
                                .font(.caption)

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
                        Button("Open Settings") { openSecuritySettings() }
                            .buttonStyle(.borderless)
                    }
                }
                .font(.caption)
                .padding(ViewConstants.secondarySpacing)
                .background(
                    RoundedRectangle(cornerRadius: ViewConstants.cornerRadius)
                        .fill(Color.primary.opacity(0.05))
                )
            }
        }
    }

    private var apkList: some View {
        APKListView(state: state)
            .environmentObject(deviceState)
            .environmentObject(statusViewModel)
            .environmentObject(configState)
    }

    private var readyDevices: [ADBDevice] {
        deviceState.devices.filter { $0.status == .device }
    }

    // MARK: - APK list

    private struct APKListView: View {
        @ObservedObject var state: InstallAPKState
        @State private var visibleItems: Set<String> = []

        var body: some View {
            if state.selectedLocation == nil {
                emptyState(
                    title: "Choose a Folder",
                    message: "Select or add a folder containing APK files."
                )
            } else if !state.hasPermission {
                emptyState(
                    title: "Folder Access Required",
                    message: "Re-choose the folder to grant access."
                )
            } else if state.apkFiles.isEmpty && !state.isScanning {
                emptyState(
                    title: "No APKs Found",
                    message: "Select or add a folder containing APK files."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: ViewConstants.cardSpacing) {
                        ForEach(Array(state.apkFiles.prefix(state.displayLimit).enumerated()), id: \.element.id) { index, file in
                            APKFileRow(file: file)
                                .environmentObject(state)
                                .disabled(!state.hasPermission)
                                .opacity(visibleItems.contains(file.id) ? 1 : 0)
                                .offset(y: visibleItems.contains(file.id) ? 0 : 20)
                                .animation(.easeOut(duration: 0.4).delay(Double(index) * 0.08), value: visibleItems)
                        }

                        if state.apkFiles.count > state.displayLimit {
                            Button {
                                state.displayLimit += 10
                                animateNewItems()
                            } label: {
                                HStack {
                                    Text("Load More")
                                    Text("(\(max(0, state.apkFiles.count - state.displayLimit)) remaining)")
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
                        }
                    }
                }
                .onChange(of: state.apkFiles) { _ in
                    animateItems()
                }
            }
        }

        private func emptyState(title: String, message: String) -> some View {
            VStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        private func animateItems() {
            visibleItems.removeAll()

            let itemsToShow = Array(state.apkFiles.prefix(state.displayLimit))
            for (index, file) in itemsToShow.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.08) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        _ = visibleItems.insert(file.id)
                    }
                }
            }
        }

        private func animateNewItems() {
            let currentVisibleCount = visibleItems.count
            let newItemsToShow = Array(state.apkFiles.prefix(state.displayLimit))

            for (index, file) in newItemsToShow.enumerated() where index >= currentVisibleCount {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index - currentVisibleCount) * 0.08) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        _ = visibleItems.insert(file.id)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func openSecuritySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openADBHelp() {
        guard let url = URL(string: AppConfig.adbHelpURL) else { return }
        NSWorkspace.shared.open(url)
    }

    private func reloadLocations() {
        locations = StorageManager.loadLocations()
            .sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending })
    }

    private func restoreInitialSelection() {
        if state.selectedLocation == nil {
            let loaded = StorageManager.loadLocations()
            if let lastPath = StorageManager.loadLastSelectedLocation(),
               let lastLocation = loaded.first(where: { $0.path == lastPath }) {
                state.selectedLocation = lastLocation
            } else {
                state.selectedLocation = loaded.first
            }
        }

        if let path = state.selectedLocation?.path {
            checkPermission(for: path)

            // If we cannot read the selected folder (common for ~/Downloads due to TCC),
            // proactively prompt the user to re-select it so we can create a bookmark.
            if !didAutoPromptForFolderAccess,
               !FilePermissionManager.shared.hasBookmark(for: path),
               !hasDirectFolderAccess(path) {
                didAutoPromptForFolderAccess = true
                chooseFolder(startingAt: path)
            }
        }
    }

    private func chooseFolder() {
        chooseFolder(startingAt: nil)
    }

    private func chooseFolder(startingAt path: String?) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.canCreateDirectories = true
        openPanel.prompt = "Choose"
        if let path {
            openPanel.directoryURL = URL(fileURLWithPath: path)
        }

        openPanel.begin { response in
            guard response == .OK, let selectedURL = openPanel.url else { return }

            Task { [weak state] in
                do {
                    try FilePermissionManager.shared.saveBookmark(for: selectedURL)

                    var currentLocations = StorageManager.loadLocations()
                    let newLocation = APKLocation(path: selectedURL.path)
                    if !currentLocations.contains(where: { $0.path == newLocation.path }) {
                        currentLocations.append(newLocation)
                        StorageManager.saveLocations(currentLocations)
                    }

                    await MainActor.run {
                        self.reloadLocations()
                        state?.selectedLocation = newLocation
                    }
                } catch {
                    statusViewModel.showMessage("Failed to save folder access: \(error.localizedDescription)", type: .error)
                }
            }
        }
    }

    private func refreshFolder() {
        guard let path = state.selectedLocation?.path else {
            chooseFolder()
            return
        }
        checkPermission(for: path)
    }

    // MARK: - Scanning / permissions

    private func hasDirectFolderAccess(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: path)
            return true
        } catch {
            return false
        }
    }

    @MainActor
    private func checkPermission(for path: String) {
        state.cancelCurrentScan()

        Task {
            // When no bookmark exists, attempt direct access first so Downloads (and
            // non-sandbox builds) work without forcing a picker round-trip.
            let hasBookmark = FilePermissionManager.shared.hasBookmark(for: path)
            let hasScopedAccess = hasBookmark ? FilePermissionManager.shared.restoreAccess(for: path) : false
            let hasDirectAccess = hasDirectFolderAccess(path)
            let hasPermission = hasScopedAccess || hasDirectAccess

            guard state.selectedLocation?.path == path else { return }
            state.hasPermission = hasPermission

            if !hasPermission {
                state.scanError = "Folder access required. Choose the folder again to grant access."
                state.apkFiles = []
                state.selectedAPKPath = nil
                state.lastScanAt = nil
                state.isScanning = false
                return
            }

            state.scanError = nil
            scanDirectory(path)
        }
    }

    @MainActor
    private func scanDirectory(_ path: String) {
        let directoryURL = URL(fileURLWithPath: path)

        state.cancelCurrentScan()
        state.isScanning = true
        state.apkFiles = []
        state.displayLimit = 10
        state.scanError = nil

        let task = Task(priority: .userInitiated) {
            do {
                try Task.checkCancellation()

                if !FilePermissionManager.shared.hasBookmark(for: path) {
                    _ = try? FilePermissionManager.shared.saveBookmark(for: directoryURL)
                }
                let hasScopedAccess = FilePermissionManager.shared.restoreAccess(for: path)

                try Task.checkCancellation()

                let files = try await Task.detached(priority: .userInitiated) {
                    try APKScanner.scan(in: directoryURL)
                }.value

                try Task.checkCancellation()

                guard state.selectedLocation?.path == path else { return }
                state.apkFiles = files
                state.lastScanAt = Date()
                state.isScanning = false
                state.hasPermission = hasScopedAccess || hasDirectFolderAccess(path)

                if let selectedPath = state.selectedAPKPath,
                   files.contains(where: { $0.path == selectedPath }) {
                    // Keep selection.
                } else {
                    state.selectedAPKPath = files.first?.path
                }
            } catch is CancellationError {
                return
            } catch {
                guard state.selectedLocation?.path == path else { return }
                state.scanError = error.localizedDescription
                state.isScanning = false
                state.hasPermission = false
            }
        }

        state.setScanTask(task)
    }

    // MARK: - Formatting

    private func displayPath(_ path: String) -> String {
        if path.hasPrefix(NSHomeDirectory()) {
            return path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        }
        return path
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var selection: Int? = 0
        var body: some View {
            InstallAPKView(state: AppState().installAPKState, selection: $selection)
                .environmentObject(StatusViewModel())
                .environmentObject(ConfigState())
                .frame(width: 740, height: 520)
        }
    }
    return PreviewWrapper()
}
