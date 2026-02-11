import SwiftUI
import AppKit

private enum SidebarSelection: String, CaseIterable, Hashable {
    case install
    case settings

    var title: String {
        switch self {
        case .install: return "Install APK"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .install: return "square.and.arrow.down"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @StateObject private var appState = AppState()
    @EnvironmentObject private var statusViewModel: StatusViewModel

    @State private var selection: SidebarSelection = .install
    @State private var isSidebarVisible = true
    @State private var didExportSnapshots = false

    var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                sidebar
                Divider()
            }
            detail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        #if DEBUG
        .task {
            await exportUISnapshotsIfRequested()
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .navigateToInstall)) { _ in selection = .install }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSettings)) { _ in selection = .settings }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isSidebarVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(isSidebarVisible ? "Hide sidebar" : "Show sidebar")
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(SidebarSelection.allCases, id: \.self) { item in
                    Button {
                        selection = item
                    } label: {
                        Label(item.title, systemImage: item.systemImage)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(selection == item ? Color.accentColor : Color.clear)
                            )
                            .foregroundStyle(selection == item ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            Text(appVersionText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 4)
        }
        .padding(12)
        .frame(width: ViewConstants.sidebarWidth, alignment: .topLeading)
    }

    private var detail: some View {
        Group {
            switch selection {
            case .settings:
                ConfigView(state: appState.configState)
                    .environmentObject(appState.deviceState)
            case .install:
                InstallAPKView(state: appState.installAPKState, selection: .constant(nil))
                    .environmentObject(appState.configState)
                    .environmentObject(appState.deviceState)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            StatusBarView(viewModel: statusViewModel)
                .padding(.horizontal, ViewConstants.primarySpacing)
                .padding(.bottom, 10)
        }
    }

    private var appVersionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (short, build) {
        case let (.some(s), .some(b)):
            return "v\(s) (\(b))"
        case let (.some(s), .none):
            return "v\(s)"
        case let (.none, .some(b)):
            return "build \(b)"
        default:
            return "version —"
        }
    }

    #if DEBUG
    private func exportUISnapshotsIfRequested() async {
        let env = ProcessInfo.processInfo.environment
        guard env["APKINSTALLER_EXPORT_UI_SNAPSHOTS"] == "1" else { return }
        guard !didExportSnapshots else { return }
        didExportSnapshots = true

        let outputDir = env["APKINSTALLER_SNAPSHOT_OUTPUT_DIR"]
            ?? "\(NSHomeDirectory())/Desktop/APKInstaller-Snapshots"

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")

        let baseDir = URL(fileURLWithPath: outputDir, isDirectory: true)
        let installURL = baseDir.appendingPathComponent("install-\(timestamp).png")
        let installAfterURL = baseDir.appendingPathComponent("install-after-\(timestamp).png")
        let settingsURL = baseDir.appendingPathComponent("settings-\(timestamp).png")

        if let adbPath = env["APKINSTALLER_SNAPSHOT_ADB_PATH"], !adbPath.isEmpty {
            StorageManager.saveADBPath(adbPath)
        }
        if let folderPath = env["APKINSTALLER_SNAPSHOT_FOLDER_PATH"], !folderPath.isEmpty {
            let location = APKLocation(path: folderPath)
            var locations = StorageManager.loadLocations()
            if !locations.contains(where: { $0.path == location.path }) {
                locations.append(location)
                StorageManager.saveLocations(locations)
            }
            StorageManager.saveLastSelectedLocation(location)
            await MainActor.run {
                appState.installAPKState.selectedLocation = location
            }
        }

        await MainActor.run { selection = .install }
        await waitForFolderScan(timeoutSeconds: 10)
        await sleepSeconds(1.0)
        await exportSnapshot(to: installURL)

        if env["APKINSTALLER_SNAPSHOT_RUN_INSTALL"] == "1" {
            await sleepSeconds(1.2)
            NotificationCenter.default.post(name: .snapshotInstallSelectedAPK, object: nil)
            await waitForInstallCompletion(timeoutSeconds: 30)
            await sleepSeconds(0.8)
            await exportSnapshot(to: installAfterURL)
        }

        await MainActor.run { selection = .settings }
        await sleepSeconds(1.0)
        await exportSnapshot(to: settingsURL)

        if env["APKINSTALLER_SNAPSHOT_QUIT"] != "0" {
            await MainActor.run {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func exportSnapshot(to url: URL) async {
        await MainActor.run {
            do {
                try WindowSnapshotExporter.exportMainWindowPNG(to: url)
            } catch {
                statusViewModel.showMessage("Snapshot export failed: \(error.localizedDescription)", type: .error)
            }
        }
    }

    private func waitForFolderScan(timeoutSeconds: TimeInterval) async {
        let start = Date()
        while Date().timeIntervalSince(start) < timeoutSeconds {
            let done = await MainActor.run {
                let s = appState.installAPKState
                return s.selectedLocation != nil && s.hasPermission && !s.isScanning && !s.apkFiles.isEmpty
            }
            if done { return }
            await sleepSeconds(0.2)
        }
    }

    private func waitForInstallCompletion(timeoutSeconds: TimeInterval) async {
        let start = Date()
        while Date().timeIntervalSince(start) < timeoutSeconds {
            let done = await MainActor.run {
                let s = appState.installAPKState
                return s.lastInstalledAPKPath != nil && s.lastInstalledAt != nil
            }
            if done { return }
            await sleepSeconds(0.2)
        }
    }

    private func sleepSeconds(_ seconds: TimeInterval) async {
        let nanos = UInt64(max(0, seconds) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanos)
    }
    #endif
}

#Preview {
    ContentView()
        .environmentObject(StatusViewModel())
}
