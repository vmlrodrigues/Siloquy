#!/usr/bin/env bash
# Archive the iOS app and upload it to App Store Connect / TestFlight — no Xcode GUI.
# One-time setup: copy testflight.config.example → testflight.config and fill it in,
# and create the app record in App Store Connect (bundle id com.victorrodrigues.siloquy.ios).
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f testflight.config ]]; then
  echo "✗ Missing testflight.config — copy testflight.config.example to testflight.config and fill it in."
  exit 1
fi
# shellcheck source=/dev/null
source testflight.config

if [[ ! -f "${ASC_KEY_PATH:-}" ]]; then
  echo "✗ App Store Connect API key not found at: ${ASC_KEY_PATH:-<unset>}"
  exit 1
fi

# A unique, always-increasing build number per upload (TestFlight requires it).
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
ARCHIVE="build/Siloquy.xcarchive"
echo "→ Build number: $BUILD_NUMBER"

echo "→ Regenerating project…"
xcodegen generate >/dev/null

echo "→ Archiving (Release)…"
rm -rf build
xcodebuild archive \
  -project Siloquy.xcodeproj \
  -scheme Siloquy \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

echo "→ Exporting + uploading to App Store Connect…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

echo "✓ Uploaded build $BUILD_NUMBER. It will appear in TestFlight after processing (~10–15 min)."
