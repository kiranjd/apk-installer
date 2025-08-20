import SwiftUI

@main
struct DevToolsApp: App {
    // Create a single instance of StatusViewModel for the entire app
    @StateObject private var statusViewModel = StatusViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Inject StatusViewModel into the environment
                .environmentObject(statusViewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 640)
        .windowResizability(.automatic)
    }
}