#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

INSTALL=false
if [[ "${1:-}" == "--install" ]]; then
  INSTALL=true
  shift
fi
CONFIG="${1:-release}"
if [[ -z "${VERSION:-}" ]]; then
  VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
fi
VERSION="${VERSION:-0.1.0}"
# UNIVERSAL=1 builds arm64 + x86_64. One build per triple: multi-arch builds go through
# the Xcode build system, which cannot resolve SwiftTerm's build plugin.
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  BIN_DIRS=()
  for triple in arm64-apple-macosx x86_64-apple-macosx; do
    swift build -c "$CONFIG" --triple "$triple"
    BIN_DIRS+=("$(swift build -c "$CONFIG" --triple "$triple" --show-bin-path)")
  done
  BIN_DIR="${BIN_DIRS[1]}"
else
  swift build -c "$CONFIG"
  BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
fi

APP="build/Macphin.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ -n "${BIN_DIRS:-}" ]]; then
  lipo -create "${BIN_DIRS[@]/%//Macphin}" -output "$APP/Contents/MacOS/Macphin"
else
  cp "$BIN_DIR/Macphin" "$APP/Contents/MacOS/Macphin"
fi
for bundle in "$BIN_DIR"/*.bundle(N); do
  cp -R "$bundle" "$APP/Contents/Resources/"
done
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Macphin</string>
  <key>CFBundleDisplayName</key><string>Macphin</string>
  <key>CFBundleIdentifier</key><string>dev.macphin.Macphin</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>Macphin</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER:-$VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Folder</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key><array><string>public.folder</string></array>
    </dict>
  </array>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSDesktopFolderUsageDescription</key><string>Macphin needs access to your Desktop to browse and manage files there.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>Macphin needs access to your Documents to browse and manage files there.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Macphin needs access to your Downloads to browse and manage files there.</string>
  <key>NSRemovableVolumesUsageDescription</key><string>Macphin needs access to removable volumes to browse and manage files on external drives.</string>
  <key>NSNetworkVolumesUsageDescription</key><string>Macphin needs access to network volumes to browse and manage files on shared servers.</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

sign_app() {
  if [[ -n "${MACPHIN_SIGN_IDENTITY:-}" ]]; then
    local keychain_flags=()
    [[ -n "${KEYCHAIN:-}" ]] && keychain_flags=(--keychain "$KEYCHAIN")
    codesign --force --deep --sign "$MACPHIN_SIGN_IDENTITY" --identifier dev.macphin.Macphin "${keychain_flags[@]}" "$APP"
    return
  fi
  if ! ./scripts/setup-signing.sh; then
    echo "warning: could not create the local signing identity; using ad-hoc signing (privacy permissions reset on every build)" >&2
    codesign --force --deep --sign - "$APP"
    return
  fi
  local keychain="$HOME/Library/Keychains/macphin-signing.keychain-db"
  local identity
  identity="$(security find-identity -p codesigning "$keychain" | awk '/Macphin Local Signing/ { print $2; exit }')"
  # codesign only finds identities in the search list, so add the keychain just for this call.
  local original=("${(@f)$(security list-keychains -d user | sed -e 's/^ *"//' -e 's/"$//')}")
  security unlock-keychain -p "macphin-local-signing" "$keychain"
  security list-keychains -d user -s "${original[@]}" "$keychain"
  trap 'security list-keychains -d user -s "${original[@]}"' EXIT
  codesign --force --deep --sign "$identity" --identifier dev.macphin.Macphin "$APP"
  security list-keychains -d user -s "${original[@]}"
  trap - EXIT
}

sign_app >/dev/null
echo "Built $APP"

if $INSTALL; then
  pkill -x Macphin 2>/dev/null || true
  rm -rf /Applications/Macphin.app
  cp -R "$APP" /Applications/Macphin.app
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Macphin.app
  echo "Installed /Applications/Macphin.app"
fi
