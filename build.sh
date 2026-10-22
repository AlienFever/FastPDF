#!/bin/zsh
# FastPDF for Mac — Copyright (C) 2026 Alienfever
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds "FastPDF for Mac.app", signs it ad-hoc, installs it to ~/Applications and registers it with Launch Services.
# Usage: ./build.sh [--no-install]
set -euo pipefail
cd "${0:A:h}"

NAME="FastPDF for Mac"
APP="build/$NAME.app"
SDK=$(xcrun --show-sdk-path --sdk macosx)

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

xcrun swiftc \
  -O -wmo \
  -swift-version 5 \
  -target arm64-apple-macos26.0 \
  -sdk "$SDK" \
  -module-name FastPDF \
  -framework AppKit -framework PDFKit \
  -Xlinker -dead_strip \
  -o "$APP/Contents/MacOS/FastPDF" \
  Sources/*.swift

cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

codesign --force --sign - --entitlements Resources/FastPDF.entitlements "$APP"

if [[ "${1:-}" != "--no-install" ]]; then
  DEST="$HOME/Applications/$NAME.app"
  mkdir -p ~/Applications
  # Quit the running copy and wait for it to exit, so the next open goes to the new build.
  pkill -x FastPDF 2>/dev/null && while pgrep -x FastPDF >/dev/null; do sleep 0.05; done || true
  rm -rf "$DEST" "$HOME/Applications/FastPDF.app"   # also removes the app's pre-rename copy
  cp -R "$APP" "$DEST"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
  echo "Installed $DEST"
fi
