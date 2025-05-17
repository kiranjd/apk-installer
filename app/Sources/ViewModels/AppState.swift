import SwiftUI

@MainActor
class AppState: ObservableObject {
    @Published var installAPKState: InstallAPKState
    @Published var configState: ConfigState
    @Published var bundleManagerState: BundleManagerState
    // Add other states if needed, e.g.:
    // @Published var commandTestState: CommandTestState

    init() {
        // Initialize states that DON'T depend on AppState first
        self.installAPKState = InstallAPKState()
        self.bundleManagerState = BundleManagerState()
        // self.commandTestState = CommandTestState() // Example
        
        // Initialize ConfigState (which now has no init dependencies)
        self.configState = ConfigState()
        
        // Now that all properties are initialized, 'self' is available.
        // Assign the AppState reference back to ConfigState.
        self.configState.appState = self
        
        // If CommandTestState also needed AppState, initialize and assign similarly:
        // self.commandTestState = CommandTestState()
        // self.commandTestState.appState = self
    }
    
    // If ConfigState init definitely requires AppState:
    // init() {
    //     self.installAPKState = InstallAPKState()
    //     self.bundleManagerState = BundleManagerState()
    //     // Initialize configState using a temporary self reference workaround (less clean)
    //     // Or refactor ConfigState's dependency
    //     self.configState = ConfigState(appState: self) // This structure requires careful handling or refactoring ConfigState
    // }
}

// --- Potential required change in ConfigState --- 
// If AppState init fails, modify ConfigState like this:
/*
 class ConfigState: ObservableObject {
     // ... other properties
     weak var appState: AppState? // Make it weak and optional
 
     init() { // Remove appState from init
         // ... initialize other properties ...
     }
     
     // Or use a setter method if appState is needed later
     func setup(appState: AppState) {
         self.appState = appState
         // ... potentially load things that depend on appState ...
     }
 
     // ... rest of ConfigState ...
 }
*/
