# APK Installer (macOS)

`APK Installer` is a native macOS app for quickly installing Android APK files onto connected devices via ADB.

<img src="app/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" alt="APK Installer App Icon" width="256" />

Latest installable release: [GitHub Releases](https://github.com/kiranjd/apk-installer/releases/latest)

https://github.com/user-attachments/assets/fe875a6d-88c4-48c9-b388-22a0ed7c4c5d

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
- `PREFERRED_DMG_SIGN_IDENTITY` (used only when `DMG_SIGN_IDENTITY` is unset)
- `NOTARIZE=1`
- `NOTARYTOOL_PROFILE`

By default, it uses `DMG_SIGN_IDENTITY` when set, otherwise falls back to the first available `Developer ID Application` identity in your keychain.

## Troubleshooting

- ADB not found:
  - Install platform-tools and click `Detect ADB` in Settings.
  - Or use `Select ADB` to choose the executable manually.
- No device detected:
  - Ensure USB debugging is enabled on the Android device.
  - Confirm `adb devices` shows a connected `device`.
- Folder permission errors:
  - Re-select the APK folder in the app to refresh bookmark permissions.

## Contributing

- Contribution guide: `CONTRIBUTING.md`
- Code of conduct: `CODE_OF_CONDUCT.md`
