import SwiftUI
import AppKit

struct ConfigView: View {
    @StateObject var state: ConfigState
    @EnvironmentObject var statusViewModel: StatusViewModel
    
    var body: some View {
        List {
            Section {
                HStack(spacing: ViewConstants.secondarySpacing) {
                    TextField("ADB Path", text: $state.adbPath)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 400)
                    Button("Run with ADB") {
                        Task {
                            // Attempt to resolve adb path by invoking adb; persist if found
                            if let resolved = await ShellCommand.detectADBPath() {
                                state.adbPath = resolved
                                StorageManager.saveADBPath(resolved)
                                statusViewModel.showMessage("ADB detected at: \(resolved)", type: .success)
                            } else {
                                statusViewModel.showMessage("Could not detect ADB. Please install Android platform-tools or select manually.", type: .error)
                            }
                        }
                    }
                }
                
                Button("Select ADB") {
                    state.showingADBPicker = true
                }
                
            } header: {
                Text("ADB Configuration")
                    .textCase(.none)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .padding(.bottom, ViewConstants.secondarySpacing)
            }

            Section {
                Toggle("Enable Device Selector", isOn: $state.deviceSelectorEnabled)
            } header: {
                Text("Device Selector")
                    .textCase(.none)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .padding(.bottom, ViewConstants.secondarySpacing)
            }

            Section {
                TextField("App Identifier", text: $state.appIdentifier)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 400)
                    .onReceive(state.$appIdentifier.dropFirst()) { _ in
                        state.saveAppIdentifier()
                    }
                
            } header: {
                Text("App Identifier")
                    .textCase(.none)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .padding(.bottom, ViewConstants.secondarySpacing)
            }
            
            // Section {
            //     DisclosureGroup("Command Test") {
            //         CommandTestView(state: state.appState.commandTestState)
            //             .padding(.vertical, ViewConstants.secondarySpacing)
            //     }
            // }
        }
        .listStyle(.plain)
        .navigationTitle("Config")
        .onAppear {
            // First launch experience: if ADB path isn't known, try to detect it now.
            if state.adbPath.isEmpty {
                Task {
                    if let resolved = await ShellCommand.detectADBPath() {
                        state.adbPath = resolved
                        StorageManager.saveADBPath(resolved)
                        statusViewModel.showMessage("ADB detected at: \(resolved)", type: .success)
                    }
                }
            }
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
                        StorageManager.saveADBPath(state.adbPath)
                    } catch {
                        print("❌ ADB selection failed: \(error.localizedDescription)")
                    }
                }
            case .failure(let error):
                print("❌ ADB selection failed: \(error.localizedDescription)")
            }
        }
        .onAppear {
            // checkAllPermissions() // No longer needed here
        }
    }
} 