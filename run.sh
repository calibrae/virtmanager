#!/bin/bash
set -e

killall VirtManager 2>/dev/null || true
sleep 0.5

echo "Building..."
xcodebuild build \
  -project VirtManager.xcodeproj \
  -scheme VirtManagerApp \
  -destination 'platform=macOS' \
  -configuration Debug \
  -quiet

APP=$(find ~/Library/Developer/Xcode/DerivedData/VirtManager-*/Build/Products/Debug -name "VirtManager.app" -maxdepth 1 | head -1)
echo "Launching $APP"
open "$APP"
