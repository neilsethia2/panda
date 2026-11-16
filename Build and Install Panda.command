#!/bin/bash
# Double-click this file to build Panda on this Mac and put it in Applications.
# Needs Xcode or the Xcode Command Line Tools.
cd "$(dirname "$0")" || exit 1

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Apple's developer tools are missing. A window will open to install them."
  echo "When that finishes, double-click this file again."
  xcode-select --install
  exit 1
fi

# Build only for this Mac's processor: faster, and all that is needed locally.
export PANDA_ARCHS="$(uname -m)"
./Scripts/build.sh || { echo; echo "Build failed. Scroll up for the first line that says error."; exit 1; }

echo
echo "==> Installing into /Applications"
pkill -x Panda 2>/dev/null
sleep 1
rm -rf "/Applications/Panda.app"
cp -R build/Panda.app "/Applications/Panda.app" || { echo "Could not copy into /Applications."; exit 1; }
open "/Applications/Panda.app"
echo "Panda is installed and running. Look for the panda in your menu bar."
