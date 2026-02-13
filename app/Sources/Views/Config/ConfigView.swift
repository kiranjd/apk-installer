import SwiftUI
import AppKit

struct ConfigView: View {
    @StateObject var state: ConfigState
    @EnvironmentObject private var statusViewModel: StatusViewModel
    @EnvironmentObject private var deviceState: ADBDeviceState
    @Environment(\.openURL) private var openURL

    @State private var adbHealth: ADBHealthState = .checking
    @State private var showResetConfirmation = false
    @State private var showADBOverrideEditor = false
    @State private var showTroubleshooting = false
    @State private var usePackageOverride = false
    @State private var packageOverrideDraft = ""
    @State private var packageOverrideError: String?
    @State private var hasInitialized = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                adbSection
                packageOverrideSection
                troubleshootingSection
            }
            .padding(ViewConstants.primarySpacing)
            .padding(.top, 14)
            .padding(.bottom, ViewConstants.primarySpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Settings")
        .onAppear {
            initializeStateIfNeeded()
            Task {
                await refreshADBHealth(showToast: false)
                deviceState.fetchDevices()
            }
        }
        .onChange(of: usePackageOverride) { enabled in
            handlePackageOverrideToggle(enabled)
        }
        .onChange(of: packageOverrideDraft) { value in
            guard usePackageOverride else { return }
            applyPackageOverrideDraft(value)
        }
        .confirmationDialog(
            "Reset ADB path + overrides?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) { resetSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the saved ADB path, package ID override, APK folders, and security bookmarks.")
        }
        .fileImporter(
            isPresented: $state.showingADBPicker,
            allowedContentTypes: [.unixExecutable],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let selectedURL = urls.first {
                    do {
                        try FilePermissionManager.shared.saveBookmark(for: selectedURL)
                        state.adbPath = selectedURL.path
                        Task { await refreshADBHealth(showToast: true) }
                    } catch {
                        statusViewModel.showMessage("ADB selection failed: \(error.localizedDescription)", type: .error)
                    }
                }
            case .failure(let error):
                statusViewModel.showMessage("ADB selection failed: \(error.localizedDescription)", type: .error)
            }
        }
    }

    // MARK: - Sections

    private var adbSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ADB")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Spacer()
                statusChip
            }

            settingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 10) {
                        Text("Resolved path")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 96, alignment: .leading)

                        Text(resolvedADBPathDisplay)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(resolvedADBPath == "Not found" ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            Task { await refreshADBHealth(showToast: true) }
                        } label: {
                            if adbHealth == .checking {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Re-check ADB")

                        Button(showADBOverrideEditor ? "Done" : "Override…") {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showADBOverrideEditor.toggle()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if showADBOverrideEditor {
                        HStack(spacing: 8) {
                            TextField("adb or /path/to/adb", text: $state.adbPath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))

                            Button("Choose ADB…") {
                                state.showingADBPicker = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    if let issue = adbIssueMessage {
                        Text(issue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            Button("Install ADB (Homebrew)") {
                                installADBWithHomebrew()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Button("Choose ADB…") {
                                state.showingADBPicker = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    HStack(spacing: 6) {
                        Text("Devices")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(deviceSummaryText)
                            .font(.caption)
                            .foregroundStyle(deviceSummaryColor)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer()

                        Button("How to enable USB debugging") {
                            guard let url = URL(string: AppConfig.adbHelpURL) else { return }
                            openURL(url)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
            }
        }
    }

    private var packageOverrideSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Package ID override (Advanced)")
                .font(.system(.title3, design: .rounded).weight(.semibold))

            settingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Only used if the APK can’t be parsed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text("Detected package ID")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("Auto (from selected APK at install time)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Use override", isOn: $usePackageOverride)
                        .toggleStyle(.switch)
                        .font(.callout)

                    if usePackageOverride {
                        TextField("com.example.app", text: $packageOverrideDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))

                        if let packageOverrideError {
                            Label(packageOverrideError, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
    }

    private var troubleshootingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showTroubleshooting.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showTroubleshooting ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12, alignment: .center)

                    Text("Troubleshooting")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            if showTroubleshooting {
                VStack(alignment: .leading, spacing: 12) {
                    if let version = adbVersionText {
                        troubleshootingInfoRow(label: "ADB version", value: version)
                    }

                    if !checkedADBPaths.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Checked paths")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(checkedADBPaths.prefix(5), id: \.self) { path in
                                    Text(path)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 8) {
                        Button("Copy Diagnostics") {
                            copyDiagnostics()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Reset Settings…", role: .destructive) {
                            showResetConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                .padding(.leading, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func troubleshootingInfoRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)

            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Derived UI

    private var resolvedADBPath: String {
        switch adbHealth {
        case .ready(let path, _, _), .tooOld(let path, _, _), .notWorking(let path, _, _, _):
            return path
        case .checking, .notDetected:
            let trimmed = state.adbPath.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Not found" : trimmed
        }
    }

    private var resolvedADBPathDisplay: String {
        if resolvedADBPath == "Not found" {
            return resolvedADBPath
        }
        if !resolvedADBPath.contains("/") {
            return "Using PATH: \(resolvedADBPath)"
        }
        return resolvedADBPath
    }

    private var adbVersionText: String? {
        switch adbHealth {
        case .ready(_, let version, _), .tooOld(_, let version, _):
            return version
        case .checking, .notWorking, .notDetected:
            return nil
        }
    }

    private var checkedADBPaths: [String] {
        switch adbHealth {
        case .ready(_, _, let checkedPaths), .tooOld(_, _, let checkedPaths), .notWorking(_, _, _, let checkedPaths), .notDetected(let checkedPaths):
            return checkedPaths
        case .checking:
            return []
        }
    }

    private var adbIssueMessage: String? {
        switch adbHealth {
        case .notDetected:
            return "ADB not found. Install Android platform-tools or choose a binary manually."
        case .notWorking(_, let message, _, _):
            return message
        case .tooOld:
            return "ADB is installed but too old. Update Android platform-tools."
        case .checking, .ready:
            return nil
        }
    }

    private var deviceSummaryText: String {
        if let error = deviceState.errorMessage, !error.isEmpty {
            return error
        }

        let ready = readyDevices
        if ready.isEmpty {
            return "No devices detected"
        }
        if ready.count == 1, let device = ready.first {
            return "1 device connected: \(device.displayName)"
        }
        return "\(ready.count) devices connected"
    }

    private var deviceSummaryColor: Color {
        if deviceState.errorMessage != nil {
            return .red
        }
        return readyDevices.isEmpty ? .orange : .green
    }

    private var readyDevices: [ADBDevice] {
        deviceState.devices.filter { $0.status == .device }
    }

    private var statusChip: some View {
        Text(adbChipTitle)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(adbChipForeground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(adbChipBackground)
            .clipShape(Capsule())
    }

    private var adbChipTitle: String {
        switch adbHealth {
        case .checking:
            return "Checking"
        case .ready:
            return "Ready"
        case .tooOld:
            return "Version too old"
        case .notDetected:
            return "Not found"
        case .notWorking(_, let message, let technicalDetails, _):
            let text = "\(message) \(technicalDetails)".lowercased()
            if text.contains("permission") || text.contains("operation not permitted") {
                return "Needs permission"
            }
            return "Not working"
        }
    }

    private var adbChipForeground: Color {
        switch adbHealth {
        case .ready:
            return .green
        case .checking:
            return .secondary
        case .tooOld, .notDetected:
            return .orange
        case .notWorking:
            return .red
        }
    }

    private var adbChipBackground: Color {
        switch adbHealth {
        case .ready:
            return Color.green.opacity(0.15)
        case .checking:
            return Color.secondary.opacity(0.18)
        case .tooOld, .notDetected:
            return Color.orange.opacity(0.18)
        case .notWorking:
            return Color.red.opacity(0.16)
        }
    }

    // MARK: - Helpers

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
    }

    private func initializeStateIfNeeded() {
        guard !hasInitialized else { return }
        hasInitialized = true

        let saved = StorageManager.loadAppIdentifier()
        if saved != AppConfig.defaultAppIdentifier {
            usePackageOverride = true
            packageOverrideDraft = saved
        } else {
            usePackageOverride = false
            packageOverrideDraft = ""
        }
    }

    private func handlePackageOverrideToggle(_ enabled: Bool) {
        packageOverrideError = nil

        if enabled {
            if packageOverrideDraft.isEmpty, state.appIdentifier != AppConfig.defaultAppIdentifier {
                packageOverrideDraft = state.appIdentifier
            }
            return
        }

        packageOverrideDraft = ""
        state.appIdentifier = AppConfig.defaultAppIdentifier
        state.saveAppIdentifier()
    }

    private func applyPackageOverrideDraft(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = validatePackageIdentifier(trimmed) {
            packageOverrideError = error
            return
        }

        packageOverrideError = nil
        state.appIdentifier = trimmed
        state.saveAppIdentifier()
    }

    private func validatePackageIdentifier(_ identifier: String) -> String? {
        if identifier.isEmpty {
            return "Package ID is required when override is enabled."
        }

        let pattern = "^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+$"
        let range = NSRange(identifier.startIndex..<identifier.endIndex, in: identifier)
        let matches = NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: identifier)
        if !matches || range.length < 3 {
            return "Use reverse-domain format, e.g. com.example.app"
        }
        return nil
    }

    private func installADBWithHomebrew() {
        let command = "brew install android-platform-tools"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)

        if let formulaURL = URL(string: "https://formulae.brew.sh/formula/android-platform-tools") {
            openURL(formulaURL)
        }

        statusViewModel.showMessage("Copied brew command and opened Homebrew page", type: .info)
    }

    private func refreshADBHealth(showToast: Bool, checkedPaths: [String]? = nil) async {
        var resolvedPath = state.adbPath.trimmingCharacters(in: .whitespacesAndNewlines)
        var allCheckedPaths = checkedPaths ?? []

        if allCheckedPaths.isEmpty {
            let report = await ADBService.detectADBPathWithReport()
            allCheckedPaths = report.checkedPaths
            if resolvedPath.isEmpty, let detected = report.resolvedPath {
                state.adbPath = detected
                resolvedPath = detected
            }
        }

        if resolvedPath.isEmpty {
            adbHealth = .notDetected(checkedPaths: allCheckedPaths)
            if showToast {
                statusViewModel.showMessage(
                    "Couldn't find adb yet. Install Android platform-tools or choose adb manually.",
                    type: .error
                )
            }
            return
        }

        if !resolvedPath.contains("/") {
            let report = await ADBService.detectADBPathWithReport()
            if let detected = report.resolvedPath {
                state.adbPath = detected
                resolvedPath = detected
                allCheckedPaths = mergeCheckedPaths(primary: allCheckedPaths, secondary: report.checkedPaths)
            }
        }

        if !allCheckedPaths.contains(resolvedPath) {
            allCheckedPaths.insert(resolvedPath, at: 0)
        }

        adbHealth = .checking
        do {
            let version = try await ADBService.adbVersion(atPath: resolvedPath)
            if isADBVersionTooOld(version) {
                adbHealth = .tooOld(path: resolvedPath, version: version, checkedPaths: allCheckedPaths)
                if showToast {
                    statusViewModel.showMessage("ADB version appears old. Consider updating platform-tools.", type: .error)
                }
            } else {
                adbHealth = .ready(path: resolvedPath, version: version, checkedPaths: allCheckedPaths)
                if showToast {
                    statusViewModel.showMessage("ADB ready", type: .success)
                }
            }
        } catch {
            let friendly = makeFriendlyADBError(error)
            adbHealth = .notWorking(
                path: resolvedPath,
                message: friendly.message,
                technicalDetails: friendly.technicalDetails,
                checkedPaths: allCheckedPaths
            )
            if showToast {
                statusViewModel.showMessage(friendly.message, type: .error)
            }
        }
    }

    private func isADBVersionTooOld(_ versionText: String) -> Bool {
        let pattern = "(\\d+)\\.(\\d+)\\.(\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: versionText, range: NSRange(versionText.startIndex..., in: versionText))
        else {
            return false
        }

        let parts: [Int] = (1...3).compactMap { index in
            let range = match.range(at: index)
            guard let swiftRange = Range(range, in: versionText) else { return nil }
            return Int(versionText[swiftRange])
        }

        guard parts.count == 3 else { return false }
        let minimum = [1, 0, 41]
        return parts.lexicographicallyPrecedes(minimum)
    }

    private func mergeCheckedPaths(primary: [String], secondary: [String]) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []
        for path in primary + secondary {
            guard !seen.contains(path) else { continue }
            seen.insert(path)
            merged.append(path)
        }
        return merged
    }

    private func makeFriendlyADBError(_ error: Error) -> (message: String, technicalDetails: String) {
        let technical = error.localizedDescription
        if let commandError = error as? CommandRunnerError {
            switch commandError {
            case .executableNotFound:
                return ("ADB was not found at the selected path.", technical)
            case .nonZeroExit:
                return ("ADB exists but returned an error.", technical)
            case .timedOut:
                return ("ADB did not respond in time.", technical)
            case .cancelled:
                return ("ADB check was cancelled.", technical)
            }
        }
        return ("Couldn't run adb version check.", technical)
    }

    private func copyDiagnostics() {
        let appVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
        let buildNumber = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "?"

        var lines: [String] = []
        lines.append("APK Installer Diagnostics")
        lines.append("App: \(appVersion) (\(buildNumber))")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")

        switch adbHealth {
        case .checking:
            lines.append("ADB: checking")
        case .ready(let path, let version, let checkedPaths):
            lines.append("ADB: ready")
            lines.append("ADB Path: \(path)")
            lines.append("ADB Version: \(version)")
            if !checkedPaths.isEmpty {
                lines.append("Checked Paths:")
                for candidate in checkedPaths.prefix(12) { lines.append("- \(candidate)") }
            }
        case .tooOld(let path, let version, let checkedPaths):
            lines.append("ADB: too old")
            lines.append("ADB Path: \(path)")
            lines.append("ADB Version: \(version)")
            if !checkedPaths.isEmpty {
                lines.append("Checked Paths:")
                for candidate in checkedPaths.prefix(12) { lines.append("- \(candidate)") }
            }
        case .notWorking(let path, let message, let technicalDetails, let checkedPaths):
            lines.append("ADB: not working")
            lines.append("ADB Path: \(path)")
            lines.append("ADB Error: \(message)")
            lines.append("ADB Technical: \(technicalDetails)")
            if !checkedPaths.isEmpty {
                lines.append("Checked Paths:")
                for candidate in checkedPaths.prefix(12) { lines.append("- \(candidate)") }
            }
        case .notDetected(let checkedPaths):
            lines.append("ADB: not detected")
            if !checkedPaths.isEmpty {
                lines.append("Checked Paths:")
                for candidate in checkedPaths.prefix(12) { lines.append("- \(candidate)") }
            }
        }

        lines.append("Devices: \(deviceSummaryText)")
        lines.append("Package Override Enabled: \(usePackageOverride ? "yes" : "no")")
        lines.append("Fallback Package ID: \(state.appIdentifier)")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        statusViewModel.showMessage("Copied diagnostics", type: .success)
    }

    private func resetSettings() {
        StorageManager.resetAll()
        FilePermissionManager.shared.clearAllBookmarks()

        state.adbPath = ""
        state.appIdentifier = StorageManager.loadAppIdentifier()

        usePackageOverride = false
        packageOverrideDraft = ""
        packageOverrideError = nil
        showADBOverrideEditor = false

        adbHealth = .checking
        Task {
            await refreshADBHealth(showToast: false)
            deviceState.fetchDevices()
        }
        statusViewModel.showMessage("Settings reset", type: .success)
    }
}

private enum ADBHealthState: Equatable {
    case checking
    case ready(path: String, version: String, checkedPaths: [String])
    case tooOld(path: String, version: String, checkedPaths: [String])
    case notWorking(path: String, message: String, technicalDetails: String, checkedPaths: [String])
    case notDetected(checkedPaths: [String])
}
