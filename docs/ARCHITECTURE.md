# Architecture

## Overview

The app is a SwiftUI macOS application with a small service layer:

- `CommandRunner`: typed process execution with timeout/cancellation.
- `ADBService`: ADB device, install, uninstall, and package operations.
- `APKScanner`: recursive APK file discovery and metadata extraction.
- `FilePermissionManager`: security-scoped bookmark persistence.
- `StorageManager`: lightweight user preferences/state persistence.

## UI

- `ContentView`: navigation shell.
- `InstallAPKView`: folder selection, scan, device selection, APK actions.
- `ConfigView`: ADB path detection/selection and runtime preferences.

## Data and Permissions

- Folder and executable access is persisted through security-scoped bookmarks.
- User settings are stored in `UserDefaults` via `StorageManager`.

## Testing

- Unit tests validate parsers and command-runner behavior.
- Integration smoke tests use a fake `adb` executable to validate command flow without physical devices.
