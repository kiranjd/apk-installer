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
            // Top line: APK filename (full width)
            Text(file.name)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(.primary)
                .help(file.name)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Bottom line: Size, modification date, and action buttons
            HStack {
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
                
                // Action buttons
                HStack(spacing: ViewConstants.secondarySpacing) {
                    if isHovered {
                        // Show full action menu on hover
                        ActionButtonWithLabel(
                            icon: "square.and.arrow.down",
                            label: "Install",
                            isRunning: isInstallTaskRunning,
                            isDeviceConnected: !deviceState.devices.isEmpty,
                            showLabel: true,
                            action: {
                                installAPK(isUpdate: false)
                            }
                        )
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        
                        ActionButtonWithLabel(
                            icon: "arrow.triangle.2.circlepath", 
                            label: "Update",
                            isRunning: isInstallTaskRunning,
                            isDeviceConnected: !deviceState.devices.isEmpty,
                            showLabel: true,
                            action: {
                                installAPK(isUpdate: true)
                            }
                        )
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        
                        ActionButtonWithLabel(
                            icon: "folder",
                            label: "Open",
                            isRunning: false,
                            isDeviceConnected: true, // Always enabled
                            showLabel: true,
                            action: {
                                NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "")
                            }
                        )
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else {
                        // Show discoverable ellipsis button when not hovered
                        Button(action: {}) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.secondary.opacity(0.1))
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .help("Hover to see available actions")
                        .opacity(isInstallTaskRunning ? 0.5 : 0.7)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        
                        // Invisible spacers to maintain consistent height
                        Spacer()
                            .frame(width: 0)
                        Spacer()
                            .frame(width: 0)
                    }
                }
                .frame(height: 28) // Fixed height to prevent card height changes
                .animation(.easeInOut(duration: 0.25), value: isHovered) // Slightly longer for smoother transitions
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
        }
    }
    
    // MARK: - Helper Methods
    
    private func installAPK(isUpdate: Bool) {
        Task {
            isInstallTaskRunning = true
            animatingGradient = true
            statusViewModel.showMessage("\(isUpdate ? "Updating" : "Installing") \(file.name)...", type: .progress)
            defer {
                isInstallTaskRunning = false
                animatingGradient = false
                // Force reset hover state when installation completes
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = false
                }
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
                                                  isUpdate: isUpdate,
                                                  device: targetDevice)
                statusViewModel.showMessage("Successfully \(isUpdate ? "updated" : "installed") \(file.name)", type: .success)
            } catch {
                statusViewModel.showMessage("Failed to \(isUpdate ? "update" : "install") \(file.name): \(error.localizedDescription)", type: .error)
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
