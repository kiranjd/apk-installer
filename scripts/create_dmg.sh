#!/bin/bash

# Version
VERSION="1.0"
DMG_NAME="DevTools"
TEAM_ID="Z4P2STPJXW" # Using the team ID from your current script
CERT_FILE="Certificates_JD.p12"
CERT_PASSWORD="1234" # Password you provided

echo "Starting DMG creation process v${VERSION}"

# Import the certificate if not already in keychain
echo "Importing certificate..."
security unlock-keychain -p "$(security find-generic-password -a ${USER} -s login -w)" login.keychain
security import "${CERT_FILE}" -P "${CERT_PASSWORD}" -k login.keychain -T /usr/bin/codesign || echo "Certificate might already be imported"

# Clean up previous build
rm -rf dist
rm -f "${DMG_NAME}.dmg"

# Create distribution directory
echo "Creating distribution directory..."
mkdir -p dist

# Copy the app
echo "Copying app to distribution folder..."
if ! cp -r build/DevTools.xcarchive/Products/Applications/DevTools.app dist/; then
    echo "Failed to copy app"
    exit 1
fi

# Sign the app with hardened runtime
echo "Signing the app..."
codesign --force --options runtime --deep --entitlements "app/DevTools.entitlements" --sign "Developer ID Application: $(security find-identity -v -p codesigning | grep "${TEAM_ID}" | head -1 | sed -E 's/.*"Developer ID Application: ([^"]+).*/\1/')" dist/DevTools.app

# Create Applications symlink
echo "Creating Applications folder symlink..."
ln -s /Applications dist/Applications

# Create DMG
echo "Creating DMG..."
hdiutil create -volname "${DMG_NAME}" -srcfolder dist -ov -format UDZO "${DMG_NAME}.dmg"

# Sign the DMG
echo "Signing the DMG..."
codesign --force --sign "Developer ID Application: $(security find-identity -v -p codesigning | grep "${TEAM_ID}" | head -1 | sed -E 's/.*"Developer ID Application: ([^"]+).*/\1/')" "${DMG_NAME}.dmg"

# Clean up
echo "Cleaning up..."
rm -rf dist

echo "DMG creation complete!"
echo "Output: ${DMG_NAME}.dmg"

# Notarizing the DMG (optional - only if you have a Developer ID)
echo "Would you like to notarize the DMG? (y/n)"
read -r response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo "Notarizing DMG..."
    xcrun notarytool submit "${DMG_NAME}.dmg" --keychain-profile "AC_APP" --team-id "${TEAM_ID}" --wait

    echo "Stapling notarization ticket..."
    xcrun stapler staple "${DMG_NAME}.dmg"
fi

echo "Process complete!"
