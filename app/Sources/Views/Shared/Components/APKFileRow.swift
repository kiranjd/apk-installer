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
    @EnvironmentObject var statusViewModel: StatusViewModel
    @EnvironmentObject var configState: ConfigState
    @State private var isInstallTaskRunning = false
    @State private var animatingGradient = false
    
    private let idleGradient = LinearGradient(gradient: Gradient(colors: [Color.primary.opacity(ViewConstants.cardBackgroundOpacity)]), startPoint: .topLeading, endPoint: .bottomTrailing)
    private let installingGradient = LinearGradient(gradient: Gradient(colors: [Color.green.opacity(0.2), Color.green.opacity(0.4), Color.green.opacity(0.2)]), startPoint: .topLeading, endPoint: .bottomTrailing)
    
    var body: some View {
        VStack(alignment: .leading, spacing: ViewConstants.secondarySpacing) {
            HStack {
                Text(file.name)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Spacer()
                
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let now = context.date
                    Text(now.timeIntervalSince(file.modificationDate) < 60
                         ? "just now"
                         : file.modificationDate.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack(spacing: ViewConstants.secondarySpacing) {
                    Button {
                    Task {
                            isInstallTaskRunning = true
                            animatingGradient = true
                            statusViewModel.showMessage("Installing \(file.name)...", type: .progress)
                            defer {
                                isInstallTaskRunning = false
                                animatingGradient = false
                            }
                            // Determine target device: prompt if auto mode and multiple devices
                            var targetDevice = deviceState.selectedDeviceID
                            if !configState.deviceSelectorEnabled && deviceState.devices.count > 1 {
                                if let chosen = promptForDevice(devices: deviceState.devices) {
                                    targetDevice = chosen
                                } else {
                                    // Canceled; abort install
                                    return
                                }
                            }
                            do {
                                try await ShellCommand.installAPK(path: file.path,
                                                                  isUpdate: false,
                                                                  device: targetDevice)
                                statusViewModel.showMessage("Successfully installed \(file.name)", type: .success)
                            } catch {
                                statusViewModel.showMessage("Failed to install \(file.name): \(error.localizedDescription)", type: .error)
                            }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .frame(width: ViewConstants.iconSize)
                    }
                    .help("Install APK with test flag")
                    .disabled(isInstallTaskRunning)
                    
                    Button {
                    Task {
                            isInstallTaskRunning = true
                            animatingGradient = true
                            statusViewModel.showMessage("Updating \(file.name)...", type: .progress)
                            defer {
                                isInstallTaskRunning = false
                                animatingGradient = false
                            }
                            // Determine target device: prompt if auto mode and multiple devices
                            var targetDevice = deviceState.selectedDeviceID
                            if !configState.deviceSelectorEnabled && deviceState.devices.count > 1 {
                                if let chosen = promptForDevice(devices: deviceState.devices) {
                                    targetDevice = chosen
                                } else {
                                    // Canceled; abort update
                                    return
                                }
                            }
                            do {
                                try await ShellCommand.installAPK(path: file.path,
                                                                  isUpdate: true,
                                                                  device: targetDevice)
                                statusViewModel.showMessage("Successfully updated \(file.name)", type: .success)
                            } catch {
                                statusViewModel.showMessage("Failed to update \(file.name): \(error.localizedDescription)", type: .error)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .frame(width: ViewConstants.iconSize)
                    }
                    .help("Update existing app")
                    .disabled(isInstallTaskRunning)
                    
                    Button {
                        NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "")
                    } label: {
                        Image(systemName: "folder")
                            .frame(width: ViewConstants.iconSize)
                    }
                    .help("Show in Finder")
                }
                .buttonStyle(HoverButtonStyle())
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .opacity(isHovered ? 1 : (isInstallTaskRunning ? 0.5 : 0))
            }
        }
        .padding(.horizontal, ViewConstants.primarySpacing)
        .padding(.vertical, ViewConstants.secondarySpacing)
        .background {
            RoundedRectangle(cornerRadius: ViewConstants.cornerRadius)
                .fill(isInstallTaskRunning ? (animatingGradient ? installingGradient : idleGradient) : idleGradient)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                .animation(isInstallTaskRunning ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default, value: animatingGradient)
        }
        .onHover { hovering in
            if !isInstallTaskRunning {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
        }
    }
}

    /// Prompts the user to select one of multiple connected devices.
    private func promptForDevice(devices: [ADBDevice]) -> String? {
        let alert = NSAlert()
        alert.messageText = "Multiple devices detected"
        alert.informativeText = "Please select a device to install the APK."
        alert.alertStyle = .informational
        devices.forEach { device in
            alert.addButton(withTitle: device.displayName)
        }
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        let first = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        let index = response.rawValue - first
        if index >= 0 && index < devices.count {
            return devices[index].id
        }
        return nil
    }

#Preview {
    let exampleFile = APKFile(name: "ExampleApp.apk", path: "/Users/test/app.apk", size: 12345678, modificationDate: .now)
    
    let statusViewModel = StatusViewModel()
    
    VStack {
        APKFileRow(file: exampleFile)
            .environmentObject(statusViewModel)
            .padding()
        
        Spacer()
        StatusBarView(viewModel: statusViewModel)
            .padding(.bottom)
    }
    .frame(width: 400)
    .padding()
} 
