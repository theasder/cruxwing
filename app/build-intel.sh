#!/bin/bash
# Produce a portable Intel-native release build. Swift's release configuration
# enables whole-module optimized code; the x86_64 target intentionally avoids a
# newer CPU-specific ISA so the app remains compatible with older Intel Macs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/orakul-Intel.app"
BIN="$APP/Contents/MacOS/MeetGPT"
DIST="$ROOT/dist"
ZIP="$DIST/orakul-Intel.zip"
SECRETS="$ROOT/Sources/MeetGPT/LocalSecrets.generated.swift"
SECRETS_BACKUP="$(mktemp "${TMPDIR:-/tmp}/orakul-secrets.XXXXXX")"
HAD_SECRETS=0
if [ -f "$SECRETS" ]; then
    cp "$SECRETS" "$SECRETS_BACKUP"
    HAD_SECRETS=1
fi
restore_secrets() {
    if [ "$HAD_SECRETS" = "1" ]; then
        cp "$SECRETS_BACKUP" "$SECRETS"
    else
        rm -f "$SECRETS"
    fi
    rm -f "$SECRETS_BACKUP"
}
trap restore_secrets EXIT

# A transferable artifact must never contain the provider keys from a local
# app/.env. MEETGPT_DIST also selects the keyless direct-provider configuration
# and sandbox profile.
rm -rf "$APP"
rm -f "$ZIP"
MEETGPT_ARCH=x86_64 \
MEETGPT_APP_BASENAME=orakul-Intel \
MEETGPT_DIST=1 \
MEETGPT_NO_INSTALL=1 \
"$ROOT/build.sh"

PLIST="$APP/Contents/Info.plist"
if [ ! -f "$PLIST" ]; then
    echo "!! fresh build did not produce $APP" >&2
    exit 1
fi
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST" 2>/dev/null || true)"
DISPLAY_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$PLIST" 2>/dev/null || true)"
if [ "$BUNDLE_ID" != "ai.orakul.desktop" ] || [ "$DISPLAY_NAME" != "orakul" ]; then
    echo "!! refusing to package an app with unexpected identity" >&2
    echo "   expected ai.orakul.desktop / orakul, got $BUNDLE_ID / $DISPLAY_NAME" >&2
    exit 1
fi

ARCHS="$(lipo -archs "$BIN")"
if [ "$ARCHS" != "x86_64" ]; then
    echo "!! expected an Intel-only executable, got: $ARCHS" >&2
    exit 1
fi

codesign --verify --deep --strict "$APP"
bash "$ROOT/assert-no-baked-secrets.sh" "$APP"
# И дословная сверка с .env: предыдущая проверка знает формы известных
# ключей, эта — сами значения, каким бы путём они в сборку ни попали.
bash "$ROOT/assert-no-env-values.sh" "$APP"

mkdir -p "$DIST"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo ">> Intel executable: $ARCHS"
echo ">> Intel app: $APP"
echo ">> Intel zip: $ZIP"
echo "   Locally signed build; use notarize.sh with a Developer ID for Gatekeeper-ready distribution."
