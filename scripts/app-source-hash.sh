#!/usr/bin/env bash
# One canonical list of inputs that determine the macOS application bundle.
# Both build.sh and audit-dmg.sh call this wrapper; copying the list between
# them once produced a green build and a permanently failing freshness audit.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

exec bash scripts/source-hash.sh \
    app/Package.swift app/Package.resolved app/build.sh app/Support \
    app/Sources/MeetGPT mvp/Package.swift mvp/Sources/CruxwingCore \
    scripts/app-source-hash.sh scripts/source-hash.sh \
    scripts/verify-swiftpm-checkouts.sh
