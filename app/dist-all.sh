#!/bin/bash
#
# Build a distributable for both supported architectures.
#
# Each arch goes through the full, already-debugged notarize.sh pipeline (its own
# scratch path under .build/<arch>, its own Developer-ID sign, its own Apple
# notarization + staple). Output in dist/:
#     orakul-AppleSilicon.zip  (+ .sha256)   arm64
#     orakul-Intel.zip         (+ .sha256)   x86_64
#
# arm64 runs first, so if the Intel leg fails the Apple Silicon artifact and
# its diagnostics are still available. Prerequisites are
# notarize.sh's: a Developer-ID identity and stored notarytool credentials.
#
# This is what the build step distributes; a single-arch build is
#     MEETGPT_ARCH=arm64 ./notarize.sh
# and remains available for a quick Apple-Silicon-only turn.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

ARCHES=(arm64 x86_64)
built=()
for arch in "${ARCHES[@]}"; do
    echo "======================================================================"
    echo ">> distributable: $arch"
    echo "======================================================================"
    MEETGPT_ARCH="$arch" "$ROOT/notarize.sh"
    # The drag-to-Applications DMG accompanies the zip: the zip invites running
    # from ~/Downloads,
    # which breaks path-tied Screen Recording/Microphone grants on later moves —
    # dmg.sh's whole reason to exist. It packages THIS arch's freshly stapled
    # bundle, then signs, notarizes and staples the image itself.
    "$ROOT/dmg.sh" "$arch"
    built+=("$arch")
done

echo ""
echo ">> both architectures done (${built[*]}):"
ls -1 "$ROOT/dist/"*.zip "$ROOT/dist/"*.dmg 2>/dev/null || true

# Packaging ends in this repository. Publishing is a separate, explicit
# maintainer action; a public build script must not mutate a sibling checkout.
echo ">> проверить свежесть и подписи:"
echo "   bash \"$ROOT/../scripts/audit-dmg.sh\" \"$ROOT/dist/orakul-AppleSilicon.dmg\" \"$ROOT/dist/orakul-Intel.dmg\""
