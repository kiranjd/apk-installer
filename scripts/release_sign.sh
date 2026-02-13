#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
SCRIPT_NAME="$(basename -- "$0")"
PROJECT_PATH="${PROJECT_PATH:-${REPO_ROOT}/APKInstaller.xcodeproj}"
SCHEME_NAME="${SCHEME_NAME:-APKInstaller}"
APP_NAME="${APP_NAME:-APKInstaller}"
DIST_ROOT="${DIST_ROOT:-${REPO_ROOT}/dist}"
ARCHIVE_PATH="${ARCHIVE_PATH:-${DIST_ROOT}/${APP_NAME}.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-${DIST_ROOT}/export}"
EXPORT_PLIST="${EXPORT_PLIST:-${EXPORT_PATH}/ExportOptions.plist}"
DMG_PATH="${DMG_PATH:-${DIST_ROOT}/${APP_NAME}.dmg}"
DEVELOPER_TEAM_ID="${DEVELOPER_TEAM_ID:-}"
NOTARIZE="${NOTARIZE:-0}"
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-textify-notary}"
DMG_SIGN_IDENTITY="${DMG_SIGN_IDENTITY:-}"
PREFERRED_DMG_SIGN_IDENTITY="${PREFERRED_DMG_SIGN_IDENTITY:-}"

usage() {
  cat <<USAGE
Usage: ${SCRIPT_NAME}

Environment:
  DEVELOPER_TEAM_ID   Team used for xcode archive export (auto-detected when unset)
  DMG_SIGN_IDENTITY   Optional exact Developer ID identity for DMG signing
  PREFERRED_DMG_SIGN_IDENTITY Optional fallback identity name when DMG_SIGN_IDENTITY is unset
  NOTARIZE            1 to notarize DMG, 0 to skip (default: ${NOTARIZE})
  NOTARYTOOL_PROFILE  Notarytool keychain profile (default: ${NOTARYTOOL_PROFILE})
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -d "${PROJECT_PATH}" ]]; then
  echo "Project not found at ${PROJECT_PATH}" >&2
  exit 1
fi

available_developer_ids() {
  security find-identity -v -p codesigning | awk -F\" '/Developer ID Application/ {print $2}'
}

is_identity_available() {
  local identity="$1"
  local identities="$2"
  [[ -n "${identity}" ]] || return 1
  echo "${identities}" | grep -Fxq "${identity}"
}

DEVELOPER_IDS="$(available_developer_ids || true)"

if [[ -z "${DMG_SIGN_IDENTITY}" && -n "${PREFERRED_DMG_SIGN_IDENTITY}" ]]; then
  if is_identity_available "${PREFERRED_DMG_SIGN_IDENTITY}" "${DEVELOPER_IDS}"; then
    DMG_SIGN_IDENTITY="${PREFERRED_DMG_SIGN_IDENTITY}"
  else
    echo "Preferred DMG identity is not available in keychain: ${PREFERRED_DMG_SIGN_IDENTITY}" >&2
  fi
fi

# Fallback: first available Developer ID Application cert in keychain.
if [[ -z "${DMG_SIGN_IDENTITY}" ]]; then
  DMG_SIGN_IDENTITY="$(echo "${DEVELOPER_IDS}" | head -n 1)"
fi

if [[ -n "${DMG_SIGN_IDENTITY}" ]] && ! is_identity_available "${DMG_SIGN_IDENTITY}" "${DEVELOPER_IDS}"; then
  echo "DMG_SIGN_IDENTITY is not available in keychain: ${DMG_SIGN_IDENTITY}" >&2
  exit 1
fi

if [[ -z "${DEVELOPER_TEAM_ID}" && -n "${DMG_SIGN_IDENTITY}" ]]; then
  DEVELOPER_TEAM_ID=$(echo "${DMG_SIGN_IDENTITY}" | sed -nE 's/.*\(([A-Z0-9]{10})\)$/\1/p')
fi

if [[ -z "${DEVELOPER_TEAM_ID}" ]]; then
  echo "Could not determine DEVELOPER_TEAM_ID. Set DEVELOPER_TEAM_ID explicitly." >&2
  exit 1
fi

echo "Using DEVELOPER_TEAM_ID=${DEVELOPER_TEAM_ID}"
if [[ -n "${DMG_SIGN_IDENTITY}" ]]; then
  echo "Using DMG_SIGN_IDENTITY=${DMG_SIGN_IDENTITY}"
fi

mkdir -p "${DIST_ROOT}" "${EXPORT_PATH}"
rm -rf "${ARCHIVE_PATH}"
# zsh fails on unmatched globs by default; (N) makes the glob expand to nothing.
rm -rf "${EXPORT_PATH}"/*.app(N) "${EXPORT_PATH}"/*.pkg(N)

cat > "${EXPORT_PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>teamID</key>
  <string>${DEVELOPER_TEAM_ID}</string>
  <key>destination</key>
  <string>export</string>
  <key>stripSwiftSymbols</key>
  <true/>
</dict>
</plist>
PLIST

xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME_NAME}" \
  -configuration Release \
  -archivePath "${ARCHIVE_PATH}" \
  -destination "generic/platform=macOS" \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_PATH}" \
  -exportOptionsPlist "${EXPORT_PLIST}"

EXPORTED_APP="${EXPORT_PATH}/${APP_NAME}.app"
if [[ ! -d "${EXPORTED_APP}" ]]; then
  echo "Exported app not found at ${EXPORTED_APP}" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "${EXPORTED_APP}"

TMP_DMG_DIR="${DIST_ROOT}/dmg-root"
rm -rf "${TMP_DMG_DIR}"
mkdir -p "${TMP_DMG_DIR}"
cp -R "${EXPORTED_APP}" "${TMP_DMG_DIR}/"
ln -s /Applications "${TMP_DMG_DIR}/Applications"

rm -f "${DMG_PATH}"
hdiutil create -volname "${APP_NAME}" -srcfolder "${TMP_DMG_DIR}" -ov -format UDZO "${DMG_PATH}"

if [[ -n "${DMG_SIGN_IDENTITY}" ]]; then
  echo "Signing DMG with ${DMG_SIGN_IDENTITY}"
  codesign --force --timestamp --sign "${DMG_SIGN_IDENTITY}" "${DMG_PATH}"
  codesign --verify --verbose=2 "${DMG_PATH}"
else
  echo "No Developer ID identity found; skipping DMG signing."
fi

if [[ "${NOTARIZE}" == "1" ]]; then
  xcrun notarytool submit "${DMG_PATH}" --wait --keychain-profile "${NOTARYTOOL_PROFILE}"
  xcrun stapler staple "${DMG_PATH}"
  xcrun stapler validate "${DMG_PATH}"
fi

spctl --assess --type open --context context:primary-signature --verbose "${DMG_PATH}" || true

echo "Release artifact: ${DMG_PATH}"
