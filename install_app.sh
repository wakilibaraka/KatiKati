#!/bin/bash
set -e
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -derivedDataPath DerivedData
APP_BUNDLE="DerivedData/Build/Products/Debug/KatiKati.app"
pkill -9 KatiKati || true
rm -rf /Applications/KatiKati.app
cp -R "$APP_BUNDLE" /Applications/KatiKati.app
codesign --force --deep -s - /Applications/KatiKati.app
open /Applications/KatiKati.app
