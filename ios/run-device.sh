#!/usr/bin/env bash
# Build Siloquy (Debug) and install + launch it on a paired iPhone — without
# ever opening Xcode. Xcode.app must be *installed* (xcodebuild and devicectl
# live inside it), but it never has to be open. This is the headless
# replacement for Xcode's Run button, for the on-device dev loop.
#
#   ./run-device.sh              # build, install, and launch on the paired phone
#   ./run-device.sh --console    # …and stream the app's stdout/stderr here
#   ./run-device.sh --device Vic # target a device whose name contains "Vic"
#
# Signing: Siloquy shares an App Group with its widget, and entitlements bind
# at sign time, so this is a real team-signed build (not the unsigned shortcut).
# The App Store Connect API key in testflight.config authorises provisioning
# updates, so the app + widget development profiles refresh headlessly.
set -euo pipefail
cd "$(dirname "$0")"

CONSOLE=0
DEVICE_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --console) CONSOLE=1; shift ;;
    --device)  DEVICE_NAME="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

[[ -f testflight.config ]] || { echo "✗ Missing testflight.config — copy testflight.config.example and fill it in." >&2; exit 1; }
source testflight.config
: "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}" "${ASC_KEY_PATH:?}"

BUNDLE_ID="com.victorrodrigues.siloquy.ios"

# --- Find a paired device -----------------------------------------------------
echo "→ Finding a paired iPhone…"
DEV_JSON=$(mktemp)
xcrun devicectl list devices --json-output "$DEV_JSON" >/dev/null 2>&1
DEVICE=$(python3 - "$DEV_JSON" "$DEVICE_NAME" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
want = (sys.argv[2] or "").lower()
for d in data.get("result", {}).get("devices", []):
    name = (d.get("deviceProperties", {}) or {}).get("name", "")
    dtype = (d.get("hardwareProperties", {}) or {}).get("deviceType", "")
    ident = d.get("identifier")
    if dtype and dtype.lower() != "iphone":
        continue
    if want and want not in name.lower():
        continue
    print("%s\t%s" % (ident, name))
    break
PY
)
rm -f "$DEV_JSON"
[[ -n "$DEVICE" ]] || {
  echo "✗ No paired iPhone found. Plug it in (or connect over Wi-Fi) and tap Trust once." >&2
  exit 1
}
DEVICE_ID="${DEVICE%%$'\t'*}"
DEVICE_LABEL="${DEVICE#*$'\t'}"
echo "  $DEVICE_LABEL ($DEVICE_ID)"

# --- Build (Debug, device, team-signed) --------------------------------------
echo "→ Regenerating project…"
xcodegen generate >/dev/null

echo "→ Building (Debug, device)…"
# generic/platform=iOS avoids depending on the exact device id at build time;
# the specific device is chosen at install. -allowProvisioningUpdates + the API
# key refresh the app and widget development profiles without any GUI.
xcodebuild build \
  -project Siloquy.xcodeproj \
  -scheme Siloquy \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/dd \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  -quiet

APP=$(find build/dd/Build/Products/Debug-iphoneos -maxdepth 1 -name "*.app" 2>/dev/null | head -1)
[[ -n "$APP" ]] || { echo "✗ Build produced no .app in build/dd/Build/Products/Debug-iphoneos" >&2; exit 1; }
echo "  built $(basename "$APP")"

# --- Install + launch --------------------------------------------------------
# Brace the variable: a bare $DEVICE_LABEL directly before the multibyte "…"
# gets its name mangled by bash 3.2 under a misconfigured locale (macOS
# Terminal exports a bare, invalid LC_CTYPE=UTF-8), tripping `set -u`.
echo "→ Installing onto ${DEVICE_LABEL}…"
# The device link can drop mid-install ("Connection reset by peer") when the phone
# sleeps or Wi-Fi hiccups. Retry once before giving actionable guidance.
install_ok=0
for attempt in 1 2 3; do
  if xcrun devicectl device install app --device "$DEVICE_ID" "$APP" >/dev/null 2>&1; then
    install_ok=1; break
  fi
  [[ $attempt -lt 3 ]] && { echo "  connection hiccup — retrying ($attempt)…"; sleep 3; }
done
if [[ $install_ok -eq 0 ]]; then
  echo "✗ Couldn't install on ${DEVICE_LABEL} — the device connection kept dropping." >&2
  echo "  Unlock the phone and keep it awake; make sure it's on the same Wi-Fi as this" >&2
  echo "  Mac (or plug in over USB), then re-run. The build is cached, so it'll be quick." >&2
  exit 1
fi

echo "→ Launching…"
if [[ $CONSOLE -eq 1 ]]; then
  echo "  (streaming console — Ctrl-C to stop)"
  xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing --console "$BUNDLE_ID"
# A launch failure isn't fatal — the install already succeeded. The usual
# cause is a locked phone (devicectl can install to it but not launch on it).
elif xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing "$BUNDLE_ID" >/dev/null 2>&1; then
  echo "✓ Siloquy is running on ${DEVICE_LABEL}. Xcode never opened."
else
  echo "✓ Installed on ${DEVICE_LABEL} — but couldn't auto-launch (is the phone locked?)."
  echo "  It's on your home screen; tap it, or unlock and re-run to launch."
fi
