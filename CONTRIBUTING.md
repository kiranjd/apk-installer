# Contributing

Thanks for contributing to APK Installer.

## Prerequisites

1. macOS 13.5+
2. Xcode 16+
3. Android platform-tools (`adb`) installed and available on `PATH` (or configurable in app Settings)

## Local Setup

1. Fork and clone the repository.
2. Open `APKInstaller.xcodeproj` in Xcode, scheme `APKInstaller`.
3. Or build from terminal:

```bash
./scripts/build_local.sh
```

## Run Tests

Run the same commands CI runs before opening a PR:

```bash
xcodebuild \
  -project APKInstaller.xcodeproj \
  -scheme APKInstaller \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project APKInstaller.xcodeproj \
  -scheme APKInstaller \
  -configuration Debug \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Optional: run the CI sanitization check locally:

```bash
rg -n "\\bMPL\\b|\\bkiran\\b|CERT_PASSWORD" app scripts config README.md CONTRIBUTING.md SECURITY.md docs LICENSE .github/workflows
git ls-files | rg "(\\.cer$|\\.p12$|xcuserdata|xcuserstate)"
```

## Development Guidelines

- Keep changes focused and reviewable.
- Add or update tests for behavior changes where practical.
- Update docs in the same PR when user-facing behavior or workflow changes.
- Avoid hardcoded machine-specific paths or sibling-repo dependencies.
- Prefer environment-driven or repo-local defaults.
- Do not commit secrets, certificates, provisioning profiles, local IDE artifacts, or generated binaries.

## Coding Notes

- Prefer deterministic process execution and explicit error handling.
- Keep UI and service changes separated when possible.
- For path configuration, support both command names on `PATH` and explicit absolute paths.

## Pull Request Guidelines

1. Link related issue(s) when available.
2. Explain what changed and why.
3. Include testing evidence (commands run and results).
4. Add screenshots/GIFs for UI changes.
5. Confirm no unrelated refactors or formatting-only churn.

## Commit Style

Conventional Commits are recommended:

- `feat: ...`
- `fix: ...`
- `docs: ...`
- `test: ...`
- `refactor: ...`
- `chore: ...`

## Security Issues

Do not open public issues for vulnerabilities. Follow `SECURITY.md` for responsible disclosure.
