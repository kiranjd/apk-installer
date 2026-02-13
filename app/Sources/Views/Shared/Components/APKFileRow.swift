import SwiftUI
import AppKit

// A button style that provides hover and press highlight for icon buttons.
private struct HoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverButton(configuration: configuration)
    }

    private struct HoverButton: View {
        let configuration: Configuration
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .padding(4)
                .background(
                    Group {
                        if configuration.isPressed {
                            Color.primary.opacity(0.2)
                        } else if isHovering {
                            Color.primary.opacity(0.1)
                        } else {
                            Color.clear
                        }
                    }
                )
                .cornerRadius(6)
                .onHover { hovering in
                    isHovering = hovering
                }
        }
    }
}

struct APKFileRow: View {
    let file: APKFile
    @State private var isHovered = false
    @EnvironmentObject private var deviceState: ADBDeviceState
    @EnvironmentObject private var installState: InstallAPKState
    @EnvironmentObject var statusViewModel: StatusViewModel
    @EnvironmentObject var configState: ConfigState
    @State private var isInstallTaskRunning = false
    @State private var installTask: Task<Void, Never>?
    @State private var animatingGradient = false
    
    private let idleGradient = LinearGradient(gradient: Gradient(colors: [Color.primary.opacity(ViewConstants.cardBackgroundOpacity)]), startPoint: .topLeading, endPoint: .bottomTrailing)
    private let installingGradient = LinearGradient(gradient: Gradient(colors: [Color.green.opacity(0.2), Color.green.opacity(0.4), Color.green.opacity(0.2)]), startPoint: .topLeading, endPoint: .bottomTrailing)
    
    private var readyDevices: [ADBDevice] {
        deviceState.devices.filter { $0.status == .device }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ViewConstants.secondarySpacing) {
            // Top line: APK filename (full width)
            Text(file.name)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(.primary)
                .help(file.name)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Bottom line: Size, modification date, and action menu
            HStack(alignment: .center) {
                Text("\(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("·")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("\(RelativeDateTimeFormatter().localizedString(for: file.modificationDate, relativeTo: Date()))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()

                // Action buttons area, restoring original layout. Replace Open with three-dots menu.
                HStack(spacing: ViewConstants.secondarySpacing) {
                    ActionButtonWithLabel(
                        icon: "square.and.arrow.down",
                        label: "Install",
                        isRunning: isInstallTaskRunning,
                        isDeviceConnected: !readyDevices.isEmpty,
                        showLabel: true,
                        action: {
                            installAPK(isUpdate: false)
                        }
                    )

                    ActionButtonWithLabel(
                        icon: "arrow.triangle.2.circlepath",
                        label: "Update",
                        isRunning: isInstallTaskRunning,
                        isDeviceConnected: !readyDevices.isEmpty,
                        showLabel: true,
                        action: {
                            installAPK(isUpdate: true)
                        }
                    )

                    MoreMenuButton(
                        isRunning: isInstallTaskRunning,
                        isDeviceConnected: !readyDevices.isEmpty,
                        onCopy: { copyAPKToClipboard() },
                        onClear: { clearStorageForAPK() },
                        onReveal: { NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "") }
                    )
                }
                .frame(height: 28)
            }
        }
        .padding(.horizontal, ViewConstants.primarySpacing)
        .padding(.vertical, ViewConstants.secondarySpacing + 3)
        .background {
            RoundedRectangle(cornerRadius: ViewConstants.cornerRadius)
                .fill(
                    isInstallTaskRunning ? (animatingGradient ? installingGradient : idleGradient) : 
                    isHovered ? 
                        LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.08), Color.blue.opacity(0.04)]), startPoint: .topLeading, endPoint: .bottomTrailing) :
                        idleGradient
                )
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                .animation(isInstallTaskRunning ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .easeInOut(duration: 0.2), value: animatingGradient)
                .animation(.easeInOut(duration: 0.2), value: isHovered)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering && !isInstallTaskRunning
            }
        }
    }
    
    // MARK: - Action Button with Hover Label
    
    private struct ActionButtonWithLabel: View {
        let icon: String
        let label: String
        let isRunning: Bool
        let isDeviceConnected: Bool
        let showLabel: Bool
        let action: () -> Void
        @State private var isButtonHovered = false
        
        private var isDisabled: Bool {
            !isDeviceConnected || isRunning
        }
        
        private var tooltipText: String {
            if !isDeviceConnected && (label == "Install" || label == "Update") {
                return "Connect a device via ADB to \(label.lowercased()) APK"
            }
            return label
        }
        
        var body: some View {
            Button(action: action) {
                HStack(spacing: 4) {
                    // Show warning icon when device not connected
                    if !isDeviceConnected && (label == "Install" || label == "Update") && showLabel {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                    
                    if showLabel {
                        Text(label)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
                .foregroundColor(
                    isDisabled ? .secondary.opacity(0.6) :
                    isButtonHovered ? .white : .secondary
                )
                .padding(.horizontal, showLabel ? 8 : 6)
                .padding(.vertical, 6)
                .frame(minHeight: 28)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            isDisabled ? Color.secondary.opacity(0.1) :
                            isButtonHovered ? Color.blue : Color.clear
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isDisabled ? Color.secondary.opacity(0.2) :
                            isButtonHovered ? Color.blue : Color.secondary.opacity(0.3),
                            lineWidth: 1
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.6 : 1.0)
            .help(tooltipText)
            .onHover { hovering in
                if !isDisabled {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isButtonHovered = hovering
                    }
                }
            }
            .onChange(of: isRunning) { running in
                if running {
                    isButtonHovered = false
                } else {
                    // Prevent sticky hover highlight after async task completion.
                    DispatchQueue.main.async {
                        isButtonHovered = false
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func installAPK(isUpdate: Bool) {
        installTask?.cancel()
        isInstallTaskRunning = true
        animatingGradient = true
        var installLogPath: String?

        let cancelAction: () -> Void = {
            Task { @MainActor in
                // Cancel is user intent; stop row animation immediately even if ADB teardown lags.
                animatingGradient = false
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = false
                }
                installTask?.cancel()
            }
        }

        let task = Task {
            await MainActor.run {
                statusViewModel.showMessage(
                    "\(isUpdate ? "Updating" : "Installing") \(file.name)…",
                    type: .progress,
                    onCancel: cancelAction
                )
            }
            defer {
                Task { @MainActor in
                    isInstallTaskRunning = false
                    animatingGradient = false
                    installTask = nil
                    // Force reset hover state when installation completes.
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHovered = false
                    }
                }
            }
            
            let ready = readyDevices
            guard !ready.isEmpty else {
                await MainActor.run {
                    statusViewModel.showMessage("No Android device connected.", type: .error)
                }
                return
            }

            let targetDevice = ready.first(where: { $0.id == deviceState.selectedDeviceID })?.id
                ?? ready.first?.id
            
            do {
                let result = try await ADBService.installAPK(
                    path: file.path,
                    isUpdate: isUpdate,
                    deviceID: targetDevice,
                    fallbackPackageIdentifier: configState.appIdentifier,
                    onProgress: { message in
                        await MainActor.run {
                            statusViewModel.showMessage(
                                message,
                                type: .progress,
                                onCancel: cancelAction
                            )
                        }
                    },
                    onLogReady: { path in
                        installLogPath = path
                    }
                )
                try Task.checkCancellation()
                await MainActor.run {
                    installState.lastInstalledAPKPath = file.path
                    installState.lastInstalledAt = Date()
                    NotificationCenter.default.post(
                        name: .apkInstallDidSucceed,
                        object: nil,
                        userInfo: ["apkPath": file.path]
                    )
                }
                await MainActor.run {
                    var completionMessage = "\(isUpdate ? "Updated" : "Installed") \(file.name)"
                    let resolvedLogPath = result.installLogPath ?? installLogPath
                    if let resolvedLogPath {
                        completionMessage += " • Log: \(resolvedLogPath)"
                    }
                    statusViewModel.showMessage(completionMessage, type: .success)
                    playCompletionSound()
                }
            } catch let commandError as CommandRunnerError {
                if case .cancelled = commandError {
                    let logSuffix = installLogSuffix(explicitPath: installLogPath, error: commandError)
                    await MainActor.run {
                        statusViewModel.showMessage("\(isUpdate ? "Update" : "Install") canceled for \(file.name)\(logSuffix)", type: .info)
                    }
                } else {
                    let logSuffix = installLogSuffix(explicitPath: installLogPath, error: commandError)
                    await MainActor.run {
                        statusViewModel.showMessage("Failed to \(isUpdate ? "update" : "install") \(file.name): \(commandError.localizedDescription)\(logSuffix)", type: .error)
                    }
                }
            } catch is CancellationError {
                let logSuffix = installLogSuffix(explicitPath: installLogPath, error: nil)
                await MainActor.run {
                    statusViewModel.showMessage("\(isUpdate ? "Update" : "Install") canceled for \(file.name)\(logSuffix)", type: .info)
                }
            } catch {
                let logSuffix = installLogSuffix(explicitPath: installLogPath, error: error)
                await MainActor.run {
                    statusViewModel.showMessage("Failed to \(isUpdate ? "update" : "install") \(file.name): \(error.localizedDescription)\(logSuffix)", type: .error)
                }
            }
        }
        installTask = task
    }

    private func installLogSuffix(explicitPath: String?, error: Error?) -> String {
        if let explicitPath, !explicitPath.isEmpty {
            return " • Log: \(explicitPath)"
        }
        if let error,
           let path = (error as NSError).userInfo[ADBService.installLogPathUserInfoKey] as? String,
           !path.isEmpty {
            return " • Log: \(path)"
        }
        return ""
    }

    // MARK: - Three-dots menu button (replaces Open)
    private struct MoreMenuButton: View {
        let isRunning: Bool
        let isDeviceConnected: Bool
        let onCopy: () -> Void
        let onClear: () -> Void
        let onReveal: () -> Void
        @State private var isButtonHovered = false

        var body: some View {
            Menu {
                Button(action: onCopy) {
                    Label("Copy APK", systemImage: "doc.on.doc")
                }
                Button(action: onClear) {
                    Label("Clear Storage", systemImage: "trash")
                }
                .disabled(!isDeviceConnected)
                Divider()
                Button(action: onReveal) {
                    Label("Show in Finder", systemImage: "folder")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(
                    isRunning ? .secondary.opacity(0.6) :
                    isButtonHovered ? .white : .secondary
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            isRunning ? Color.secondary.opacity(0.1) :
                            isButtonHovered ? Color.blue : Color.clear
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isRunning ? Color.secondary.opacity(0.2) :
                            isButtonHovered ? Color.blue : Color.secondary.opacity(0.3),
                            lineWidth: 1
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(isRunning)
            .onHover { hovering in
                if !isRunning {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isButtonHovered = hovering
                    }
                }
            }
            .onChange(of: isRunning) { running in
                if running {
                    isButtonHovered = false
                } else {
                    DispatchQueue.main.async {
                        isButtonHovered = false
                    }
                }
            }
        }
    }

    private func copyAPKToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let url = URL(fileURLWithPath: file.path)
        pasteboard.writeObjects([url as NSURL])
        statusViewModel.showMessage("Copied APK to clipboard: \(file.name)", type: .info)
    }

    private func clearStorageForAPK() {
        Task {
            // Determine package id from APK; fallback to configured identifier
            let pkgId: String
            do {
                pkgId = try await ADBService.packageIdentifier(from: file.path)
            } catch {
                pkgId = configState.appIdentifier
            }
            let targetDevice = readyDevices.first(where: { $0.id == deviceState.selectedDeviceID })?.id
                ?? readyDevices.first?.id
            do {
                try await ADBService.clearAppData(identifier: pkgId, deviceID: targetDevice)
                statusViewModel.showMessage("Cleared app data for \(pkgId)", type: .success)
            } catch {
                statusViewModel.showMessage("Failed to clear app data for \(pkgId): \(error.localizedDescription)", type: .error)
            }
        }
    }

    @MainActor
    private func playCompletionSound() {
        if let sound = NSSound(named: NSSound.Name("Glass")) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }
    
}

#Preview {
    let exampleFile = APKFile(name: "ExampleApp.apk", path: "/path/to/app.apk", size: 12345678, modificationDate: .now)
    
    let statusViewModel = StatusViewModel()
    let installState = InstallAPKState()
    let deviceState = ADBDeviceState()
    let configState = ConfigState()
    
    VStack {
        APKFileRow(file: exampleFile)
            .environmentObject(installState)
            .environmentObject(deviceState)
            .environmentObject(configState)
            .environmentObject(statusViewModel)
            .padding()
        
        Spacer()
        StatusBarView(viewModel: statusViewModel)
            .padding(.bottom)
    }
    .frame(width: 400)
    .padding()
} 
