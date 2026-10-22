#!/bin/zsh
# FastPDF — Copyright (C) 2026 Alienfever
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds FastPDF.app, signs it ad-hoc, installs it to ~/Applications and registers it with Launch Services.
# Usage: ./build.sh [--no-install]
set -euo pipefail
cd "${0:A:h}"

APP=build/FastPDF.app
SDK=$(xcrun --show-sdk-path --sdk macosx)

rm -rf "$APP"
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

if [[ -n "${NOSANDBOX:-}" ]]; then codesign --force --sign - "$APP"; else codesign --force --sign - --entitlements Resources/FastPDF.entitlements "$APP"; fi

if [[ "${1:-}" != "--no-install" ]]; then
  DEST=~/Applications/FastPDF.app
  mkdir -p ~/Applications
  pkill -x FastPDF 2>/dev/null && while pgrep -x FastPDF >/dev/null; do sleep 0.05; done || true
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
  echo "Installed $DEST"
fi
