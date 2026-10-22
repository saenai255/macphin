#!/bin/zsh
# Packages build/Macphin.app into build/Macphin-<version>.dmg with an Applications shortcut.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Macphin.app"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")}"
DMG="build/Macphin-$VERSION.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "Macphin $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
echo "$DMG"
