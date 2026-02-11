# Contributing

## Setup

1. Install Xcode 16+.
2. Ensure `adb` is available.
3. Open `APKInstaller.xcodeproj` and use scheme `APKInstaller`.

## Development Flow

1. Make focused changes.
2. Run build and tests locally:

```bash
./scripts/build_local.sh
xcodebuild -project APKInstaller.xcodeproj -scheme APKInstaller -configuration Debug CODE_SIGNING_ALLOWED=NO test
```

3. Update docs when behavior changes.

## Style

- Keep changes small and reviewable.
- Prefer explicit types and deterministic process execution.
- Avoid hardcoding personal/team-specific identifiers in source.

## Security

Do not commit certificates, provisioning profiles, or credentials. See `SECURITY.md`.
