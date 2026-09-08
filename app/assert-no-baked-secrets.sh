#!/bin/bash
# assert-no-baked-secrets.sh <orakul.app | binary>
#
# Fail-safe secret gate for distribution. A keyless dist build
# (MEETGPT_DIST=1) reads provider credentials from the user's Keychain, so the
# shipped bundle must contain NO provider or org secrets. This scans every regular file
# for known key shapes and exits non-zero if any are found — appstore.sh
# runs it BEFORE productbuild/upload so a misbuilt (non-DIST, key-baked) binary
# can never be packaged for the store. It redacts any match so the gate itself
# never prints a full secret.
set -euo pipefail

TARGET="${1:?usage: assert-no-baked-secrets.sh <orakul.app|binary>}"
if [ -d "$TARGET" ]; then
    BIN="$TARGET/Contents/MacOS/MeetGPT"
    SCAN_ROOT="$TARGET"
else
    BIN="$TARGET"
    case "$TARGET" in
        *.app/*) SCAN_ROOT="${TARGET%%.app/*}.app" ;;
        *)       SCAN_ROOT="$TARGET" ;;
    esac
fi
[ -f "$BIN" ] || { echo "!! no binary at $BIN" >&2; exit 2; }

# Provider / API key shapes — deliberately specific so ordinary strings don't
# match: OpenAI/DeepSeek/Moonshot (sk-…), Anthropic (sk-ant-…), Google AI and
# OAuth clients, GitHub, AWS, Slack, private keys, and inline bearer tokens.
# The keyless build emits empty string literals for all of these, so a clean
# scan is expected.
#
# The (?<![A-Za-z0-9_-]) lookbehind is load-bearing. Without it `sk-` matched
# MID-WORD, and the bundled skill id `risk-management-specialist` — a router seed
# for the Risks button, present in every build — read as "ri" + "sk-management-
# specialist" and tripped the scan. This guard therefore failed on every run,
# keyless or not, which either blocks release packaging outright or trains
# everyone to wave it through. A guard that always fires protects nothing.
#
# perl rather than grep -E: BSD grep (macOS) has no lookbehind support.
PATTERN='(?<![A-Za-z0-9_-])(sk-ant-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9_-]{20,}|GOCSPX-[A-Za-z0-9_-]{10,}|[0-9]{11,}-[a-z0-9]{20,}\.apps\.googleusercontent\.com|AIza[A-Za-z0-9_-]{30,}|ghp_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|[Bb]earer [A-Za-z0-9._-]{24,})'

HITS="$(find "$SCAN_ROOT" -type f -print0 2>/dev/null \
        | xargs -0 strings -a 2>/dev/null \
        | perl -nle "print \$1 while /$PATTERN/g" | sort -u || true)"
if [ -n "$HITS" ]; then
    echo "!! BAKED SECRET DETECTED in $SCAN_ROOT — refusing to package." >&2
    echo "   A public Orakul build must be keyless. Rebuild with MEETGPT_DIST=1." >&2
    echo "   Offending token shapes:" >&2
    printf '%s\n' "$HITS" | sed -E 's/(.{6}).*/   \1… [redacted]/' >&2
    exit 1
fi
echo ">> secret scan clean: no provider/org keys in $(basename "$SCAN_ROOT")"
