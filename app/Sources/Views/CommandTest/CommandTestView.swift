import SwiftUI

struct CommandTestView: View {
    @StateObject var state: CommandTestState
    
    var body: some View {
        VStack(alignment: .leading, spacing: ViewConstants.primarySpacing) {
            TextField("Enter shell command", text: $state.command)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            
            Button("Run Command") {
                runCommand()
            }
            .disabled(state.command.isEmpty || state.isRunning)
            
            if !state.output.isEmpty {
                ScrollView {
                    Text(state.output)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 300)
                .padding(ViewConstants.secondarySpacing)
                .background {
                    RoundedRectangle(cornerRadius: ViewConstants.cornerRadius)
                        .fill(Color.primary.opacity(ViewConstants.cardBackgroundOpacity))
                }
            }
        }
        .padding(ViewConstants.primarySpacing)
    }
    
    private func runCommand() {
        state.isRunning = true
        state.output = "Running command...\n"
        
        Task {
            do {
                let process = Process()
                let pipe = Pipe()
                
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", state.command]
                process.standardOutput = pipe
                process.standardError = pipe
                
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let commandOutput = String(data: data, encoding: .utf8) ?? ""
                
                await MainActor.run {
                    state.output += "\nExit code: \(process.terminationStatus)\n"
                    state.output += "Output:\n\(commandOutput)"
                    state.isRunning = false
                }
            } catch {
                await MainActor.run {
                    state.output += "\nError: \(error.localizedDescription)"
                    state.isRunning = false
                }
            }
        }
    }
} 