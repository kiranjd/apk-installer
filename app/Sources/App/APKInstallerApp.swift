import SwiftUI

@main
struct APKInstallerApp: App {
    @StateObject private var statusViewModel = StatusViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(statusViewModel)
                .frame(
                    minWidth: AppConfig.windowWidth,
                    idealWidth: AppConfig.windowWidth,
                    maxWidth: AppConfig.windowWidth,
                    minHeight: AppConfig.windowHeight,
                    idealHeight: AppConfig.windowHeight,
                    maxHeight: AppConfig.windowHeight
                )
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: AppConfig.windowWidth, height: AppConfig.windowHeight)
        .windowResizability(.contentSize)
        .commands {
            // Standard macOS shortcut: Cmd+, opens Settings.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .navigateToSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandMenu("Navigate") {
                Button("Install APK") {
                    NotificationCenter.default.post(name: .navigateToInstall, object: nil)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Settings") {
                    NotificationCenter.default.post(name: .navigateToSettings, object: nil)
                }
                .keyboardShortcut("2", modifiers: .command)
            }
        }
    }
}
