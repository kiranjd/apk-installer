This `ContentView.swift` is the root view of a macOS SwiftUI app for Android APK management. Here's the core functionality:

**Main Features**:

1. **APK Management** 🔧

- Scans directories recursively for APK files
- Shows file metadata (size, mod date)
- Install/update APKs via ADB
- Quick Finder access

2. **Configuration** ⚙️

- Stores ADB path (with secure file picker)
- Manages watched APK folders
- Uses macOS security-scoped resources

3. **UI Structure** 🖥

- Split view navigation (sidebar + detail)
- Responsive hover effects
- Animated scanning status
- Load-more pagination
- Error handling with user-friendly messages

**Key Components**:

- `InstallAPKView`: Main APK listing/actions
- `ConfigView`: Settings/configuration
- `APKFileRow`: Individual APK file UI
- `ShellCommand`: Handles ADB interactions
- `StorageManager`: Persistent storage

Built with macOS design patterns:

- Uses `NSWorkspace` for Finder integration
- `NSOpenPanel` for directory selection
- Visual effects via `NSVisualEffectView`
- System preferences deep linking

The app follows macOS human interface guidelines with subtle animations, proper spacing, and platform-appropriate controls.
