# APK Installer (macOS)

`APK Installer` is a native macOS app for quickly installing Android APK files onto connected devices via ADB.

## Demo Video

https://github.com/kiranjd/apk-installer/releases/download/media-2026-02-12/apk-installer.mp4

Tracking issue: [#1](https://github.com/kiranjd/apk-installer/issues/1)

## Features

- Scan one or more folders recursively for APK files.
- Install or update APKs on a selected connected device.
- Clear app data for an APK package.
- Persist folder and executable permissions using security-scoped bookmarks.

## Requirements

- macOS 13.5+
- Xcode 16+
- Android platform-tools (`adb`) installed

## Build and Run (Local)

```bash
./scripts/build_local.sh
```

You can also run directly in Xcode:

- Project: `APKInstaller.xcodeproj`
- Scheme: `APKInstaller`

## Tests

```bash
xcodebuild \
  -project APKInstaller.xcodeproj \
  -scheme APKInstaller \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## Release Signing (Optional)

The release script is environment-driven and does not store secrets in-repo.

```bash
./scripts/release_sign.sh
```

Useful variables:

- `DEVELOPER_TEAM_ID`
- `DMG_SIGN_IDENTITY`
- `PREFER_VIBECODE_CERT=1` (default)
- `VIBECODE_PACKAGE_SCRIPT` (defaults to `../vibe-code/scripts/package_dmg.sh`)
- `NOTARIZE=1`
- `NOTARYTOOL_PROFILE`

By default, it prefers the `DMG_SIGN_IDENTITY` configured in `vibe-code` (if that cert exists in your keychain), then falls back to the first available `Developer ID Application` identity.

## Troubleshooting

- ADB not found:
  - Install platform-tools and click `Detect ADB` in Settings.
  - Or use `Select ADB` to choose the executable manually.
- No device detected:
  - Ensure USB debugging is enabled on the Android device.
  - Confirm `adb devices` shows a connected `device`.
- Folder permission errors:
  - Re-select the APK folder in the app to refresh bookmark permissions.
