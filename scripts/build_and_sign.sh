#!/bin/bash

# Configuration
APP_NAME="DevTools"
TEAM_ID="Z4P2STPJXW"
CERT_FILE="Certificates_JD.p12"
CERT_PASSWORD="1234"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting build process for ${APP_NAME}${NC}"

# Step 1: Import certificate
echo -e "${YELLOW}Importing certificate...${NC}"
security unlock-keychain -p "$(security find-generic-password -a ${USER} -s login -w)" login.keychain
security import "${CERT_FILE}" -P "${CERT_PASSWORD}" -k login.keychain -T /usr/bin/codesign || echo "Certificate might already be imported, or password might be incorrect."

# Step 2: Build and archive the app
echo -e "${YELLOW}Building and archiving the app...${NC}"
xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "${APP_NAME}" -configuration Release clean archive -archivePath "build/${APP_NAME}.xcarchive"

if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed. Exiting.${NC}"
    exit 1
fi

# Step 3: Export the app with proper signing
echo -e "${YELLOW}Exporting signed app...${NC}"
xcodebuild -exportArchive -archivePath "build/${APP_NAME}.xcarchive" -exportOptionsPlist "config/exportOptions.plist" -exportPath "build/export"

if [ $? -ne 0 ]; then
    echo -e "${RED}Export failed. Exiting.${NC}"
    exit 1
fi

# Step 4: Create distribution directory
echo -e "${YELLOW}Creating distribution directory...${NC}"
rm -rf dist
mkdir -p dist

# Step 5: Copy the exported app
echo -e "${YELLOW}Copying app to distribution folder...${NC}"
cp -r "build/export/${APP_NAME}.app" dist/

# Step 6: Verify the app is properly signed
echo -e "${YELLOW}Verifying app signature...${NC}"
codesign -vvv --deep --strict dist/${APP_NAME}.app

# Step 7: Create Applications symlink for drag-and-drop installation
echo -e "${YELLOW}Creating Applications folder symlink...${NC}"
ln -s /Applications dist/Applications

# Step 8: Create the DMG
echo -e "${YELLOW}Creating DMG...${NC}"
hdiutil create -volname "${APP_NAME}" -srcfolder dist -ov -format UDZO "${APP_NAME}.dmg"

# Step 9: Sign the DMG
echo -e "${YELLOW}Signing the DMG...${NC}"
# Find the Developer ID Application certificate associated with the Team ID
SIGNING_IDENTITY_LINE=$(security find-identity -v -p codesigning | grep "Developer ID Application:" | grep "${TEAM_ID}" | head -n 1)

SIGNED_DMG=false # Default to false
if [ -z "$SIGNING_IDENTITY_LINE" ]; then
    echo -e "${RED}Error: Could not find 'Developer ID Application' certificate for Team ID ${TEAM_ID} in keychain.${NC}"
    echo -e "${YELLOW}Verify the correct .p12 was imported into the login keychain and contains a 'Developer ID Application' certificate.${NC}"
    echo -e "${YELLOW}Skipping DMG signing.${NC}"
else
    # Extract the full identity name (e.g., "Developer ID Application: Your Name (TEAMID)")
    SIGNING_IDENTITY=$(echo "$SIGNING_IDENTITY_LINE" | sed -E 's/^[[:space:]]*[0-9]+\)[[:space:]]+[0-9A-F]+[[:space:]]+\"([^\"]+)\".*/\1/')
    echo -e "${GREEN}Found signing identity: ${SIGNING_IDENTITY}${NC}"
    codesign --force --sign "${SIGNING_IDENTITY}" "${APP_NAME}.dmg"
    if [ $? -ne 0 ]; then
        echo -e "${RED}DMG signing failed.${NC}"
    else
        echo -e "${GREEN}DMG signing successful.${NC}"
        SIGNED_DMG=true
    fi
fi

# Step 9.5 (Optional): Apply quarantine attribute for local testing simulation
echo -e "${YELLOW}Apply quarantine attribute to DMG for local testing? (y/n)${NC}"
read -r apply_quarantine
if [[ "$apply_quarantine" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    if [ -f "${APP_NAME}.dmg" ]; then
        echo -e "${YELLOW}Applying quarantine attribute to ${APP_NAME}.dmg...${NC}"
        # This command might require sudo privileges
        sudo xattr -w com.apple.quarantine "0081;$(date +%s);Safari;$(uuidgen)" "${APP_NAME}.dmg"
        if [ $? -ne 0 ]; then
            echo -e "${RED}Failed to apply quarantine attribute. Might require sudo password or Full Disk Access for Terminal.${NC}"
        else
            echo -e "${GREEN}Quarantine attribute applied. Try opening the DMG now to test Gatekeeper behavior.${NC}"
        fi
    else
        echo -e "${RED}DMG file not found, cannot apply quarantine attribute.${NC}"
    fi
fi

# Step 10: Notarize the DMG (optional - requires Apple Developer account)
echo -e "${YELLOW}Would you like to notarize the DMG? (y/n)${NC}"
read -r response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    if [ "$SIGNED_DMG" = true ]; then
        echo -e "${YELLOW}Notarizing DMG...${NC}"
        # Ensure you have run: xcrun notarytool store-credentials "AC_APP" --apple-id your_id --team-id your_team_id --password your_app_specific_password
        xcrun notarytool submit "${APP_NAME}.dmg" --keychain-profile "AC_APP" --team-id "${TEAM_ID}" --wait

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Notarization successful.${NC}"
            echo -e "${YELLOW}Stapling notarization ticket...${NC}"
            xcrun stapler staple "${APP_NAME}.dmg"
            if [ $? -ne 0 ]; then
                echo -e "${RED}Stapling failed.${NC}"
            else
                echo -e "${GREEN}Stapling successful.${NC}"
            fi
        else
            echo -e "${RED}Notarization failed. Check credentials and previous logs.${NC}"
        fi
    else
        echo -e "${RED}Skipping notarization because DMG signing failed or was skipped.${NC}"
    fi
fi

# Step 11: Clean up
echo -e "${YELLOW}Cleaning up...${NC}"
rm -rf dist

echo -e "${GREEN}Build complete!${NC}"
echo -e "${GREEN}Output: ${APP_NAME}.dmg${NC}"
echo -e "${YELLOW}You can distribute this DMG to your colleagues.${NC}"
