#!/bin/bash
# Wipes TCC entries for Orakul so macOS prompts again on next launch.
# Use this when you've rebuilt the app and "Screen Recording" is stuck.
set -e

BID="ai.orakul.desktop"

echo ">> Killing any running Orakul"
pkill -x MeetGPT || true

echo ">> tccutil reset ScreenCapture $BID"
tccutil reset ScreenCapture "$BID" || true

echo ">> tccutil reset Microphone $BID"
tccutil reset Microphone "$BID" || true

cat <<EOF

>> Done.

Next steps:
  1. Open System Settings → Privacy & Security → Screen Recording.
     If an old Orakul entry is still there, remove it with the "−" button.
  2. Do the same under Privacy & Security → Microphone.
  3. Open the fresh build:
       open "/Applications/orakul.app"
  4. Press Record. macOS should prompt for both permissions — grant them.
  5. Quit Orakul and open it again (permissions only take effect after relaunch).
EOF
