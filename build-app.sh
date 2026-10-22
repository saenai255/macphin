#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/Macphin.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Macphin" "$APP/Contents/MacOS/Macphin"
for bundle in "$BIN_DIR"/*.bundle(N); do
  cp -R "$bundle" "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Macphin</string>
  <key>CFBundleDisplayName</key><string>Macphin</string>
  <key>CFBundleIdentifier</key><string>dev.macphin.Macphin</string>
  <key>CFBundleExecutable</key><string>Macphin</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null
echo "Built $APP"
