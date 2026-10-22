#!/bin/zsh
# CommandLineTools ship swift-testing outside the default search paths.
set -euo pipefail
cd "$(dirname "$0")"
DEV=/Library/Developer/CommandLineTools/Library/Developer
if xcode-select -p | grep -q Xcode.app; then exec swift test; fi
swift test -Xswiftc -F$DEV/Frameworks -Xlinker -F$DEV/Frameworks \
  -Xlinker -rpath -Xlinker $DEV/Frameworks -Xlinker -rpath -Xlinker $DEV/usr/lib
