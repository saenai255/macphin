# Developing Macphin

Macphin is a Swift package (SwiftUI + AppKit) with no Xcode project. Local builds take their version from the latest tag, or 0.1.0 without one.

## Build and run

Requires macOS 15+ and a Swift 6 toolchain (Command Line Tools are enough).

```sh
./build-app.sh            # builds build/Macphin.app (release)
open build/Macphin.app
./build-app.sh --install  # also copies it to /Applications, replacing a running copy
./test.sh                 # runs the test suite

UNIVERSAL=1 VERSION=0.2.0 ./build-app.sh   # arm64 + x86_64 (needs Xcode), with a version number
./scripts/make-dmg.sh                       # build/Macphin-<version>.dmg
```

`swift run` also works for quick iteration.

The first `./build-app.sh` creates a self-signed "Macphin Local Signing" certificate in its own keychain (`~/Library/Keychains/macphin-signing.keychain-db`) and signs every build with it, so macOS keeps Macphin's privacy permissions (Full Disk Access, Desktop, Documents) across rebuilds. Set `MACPHIN_SIGN_IDENTITY` to use a real Developer ID instead. To regenerate the icon, run `swift scripts/make-icon.swift`.

For UI checks without screen-recording permission, `MACPHIN_SNAPSHOT_DIR=/some/dir build/Macphin.app/Contents/MacOS/Macphin` renders a scripted tour of the UI to PNG files (optionally start in a folder with `MACPHIN_SNAPSHOT_START`). It uses separate preferences and does not change your settings.

## Releasing

Push a tag:

```bash
git tag v0.2.0 && git push origin v0.2.0
```

The `Release` workflow builds a universal app, signs it, packages a DMG, publishes a GitHub release and bumps the cask in [saenai255/homebrew-tap](https://github.com/saenai255/homebrew-tap).

Repository secrets:

| Secret | Purpose |
| --- | --- |
| `SIGNING_P12` | Base64 of the "Macphin Release Signing" identity (.p12). It must stay the same across releases so users keep their privacy grants after updating. |
| `SIGNING_P12_PASSWORD` | Password for that .p12. |
| `TAP_TOKEN` | Fine-grained token with Contents read/write on `saenai255/homebrew-tap`. Without it, the workflow prints the new version and sha256 to update the cask by hand. |
