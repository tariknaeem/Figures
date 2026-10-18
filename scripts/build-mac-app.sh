#!/bin/bash
# Builds build/Figures.app with the Command Line Tools (full Xcode not required).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Figures
binary="$(swift build -c release --show-bin-path)/Figures"
app="build/Figures.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Figures"
cp Apple/macOS-Info.plist "$app/Contents/Info.plist"
cp Apple/Icon/Figures.icns "$app/Contents/Resources/Figures.icns"
# Ad-hoc signature: runs on this Mac; distribution needs a Developer ID.
codesign --force --sign - "$app"
echo "Built $app"
