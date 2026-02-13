## Session Notes

- Use app-window-only screenshots (not region crops), preferably via `peekaboo` + `screencapture -l <window_id>`.
- Iterate UI/UX with Gemini Pro scoring until overall score is `> 8.0`.
- Capture both primary screens each round: `Install APK` and `Settings`.
- Keep sidebar open by default.
- Tone/visual direction: minimalistic, polished, beautiful; bigger, simpler, clearer text.
- User prefers compact UI: smaller text and denser layout; avoid oversized typography.
- Always capture full app window screenshots (Install + Settings), not cropped regions.
- User wants an orange color scheme, rounded/bubbly icons, and flat bold colors across the app.
- Release build can render blank with `NavigationSplitView` persisted UI state; prefer deterministic custom sidebar/detail shell.
- Settings page should use rounded grouped cards with bold section headers, matching the Dictation Hotkeys-style reference.
- Settings simplified: removed device-picker toggle UI; device picker is now always shown on Install screen; reduced separators/copy for minimal layout.
- Settings UX pass: failure-first ADB flow (Install ADB CTA when broken), read-only resolved path + status chip, package ID override advanced with validation, troubleshooting disclosure for diagnostics/reset.
- When asked for UI screenshots, capture app-window-only (bounds crop), not full-screen desktop.
- Avoid HStack-only top install controls; use Grid/Form-style layout to prevent overlap/wrapping at fixed app widths.
- Emulator detection fix: device polling no longer cancels in-flight ADB calls (prevents perpetual empty list), and Install device picker now shows all discovered devices (including offline/unauthorized) instead of only `.device` entries.
- User wants APK app to auto-launch immediately after successful install/update.
- Toast close on progress should cancel running install/update and show canceled status.
- Auto-open fallback cannot rely on aapt/java; use installed package path diff via pm list packages -f.

- Install flow requirement: on Install, remove existing app with same package ID before install; reuse one progress toast with stage updates (resolve/remove/install/update/open).
- Package-ID extraction guardrail: requires Android `build-tools` (`aapt`/`aapt2`) in `~/Library/Android/sdk/build-tools/*`; otherwise detection falls back and can be unreliable.
- On this machine, Homebrew `apkanalyzer` was unreliable ("Cannot locate latest build tools"); SDK `cmdline-tools/latest/bin/apkanalyzer` worked once Java/build-tools were present.
- Reliability guardrail: never use placeholder `com.company.app` fallback for uninstall/open; require resolved package ID (or explicit override) for Install flow.
- Reliability guardrail: pause ADB device polling while install/update runs to avoid mid-flight device selection churn.
- Launch verification guardrail: use `dumpsys activity activities` (`topResumedActivity`/`ResumedActivity`) first; `dumpsys window` is fallback only.
- Reliability guardrail: `CommandRunner` must drain stdout/stderr concurrently; waiting for process exit first can deadlock long adb commands.
- Launch guardrail: avoid `adb shell monkey` as primary/fallback opener; prefer `am start -W -a MAIN -c LAUNCHER -p <package>`.
- Device UX guardrail: manual "Refresh devices" must still work during install/update; polling pause should disable timer only, not explicit refresh.
- Device-state guardrail: use one shared `ADBDeviceState` across Install + Settings; separate instances drift and show inconsistent emulator lists.
- Device preflight guardrail: `adb -s <serial> get-state` can transiently report offline/unknown; retry for a short window before failing install.
- Test isolation guardrail: integration tests must never write `adb_path` in app defaults; use `APKINSTALLER_ADB_PATH_OVERRIDE` env var for fake adb.
- User workflow preference: always kill existing APKInstaller process before building and launching a new debug build.
- UX preference: app launch after install/update is best-effort background behavior; do not show an "Opening app…" progress stage or include launch status in success toast.
- Reliability guardrail: every install/update attempt should emit a timestamped command trace file under `~/Library/Logs/APKInstaller/installs/` (adb + aapt/apkanalyzer + stage transitions + outcome).
- Logging guardrail: install/update trace log must flush per-line during execution so live tailing shows stalls immediately; include elapsed delta per line.
- Reliability guardrail: never run blocking pipe reads in MainActor-inherited Task; use background-queue async readers so command timeouts (e.g., adb uninstall) can still fire.
- UX guardrail: when user taps cancel on install/update, stop row flashing animation immediately (don’t wait for ADB command teardown).
- Core-path guardrail: install/update pipeline must hard-timeout and fail fast (120s budget) rather than chaining optional waits indefinitely.
- Core-path guardrail: never preflight every adb command with `adb start-server`; execute target adb command directly to avoid daemon-bootstrap hangs blocking install/update.

- Test guardrail: set `APKINSTALLER_SKIP_POST_INSTALL_LAUNCH=1` in integration/e2e tests to avoid detached best-effort launch leaking across tests.
- Docs preference: README "Demo Video" should render as an embedded player with a direct-link fallback, not a bare URL.
- Docs guardrail: In GitHub README, keep `<video ...></video>` opening tag on one line; multiline attribute formatting can render as literal text.

- Contributor portability guardrail: avoid committed absolute user-home paths or sibling-repo defaults (for example `../vibe-code`) in scripts/config; use env-driven or repo-local defaults.
