#!/usr/bin/env bash
# Genera le cartelle di piattaforma mancanti e applica le personalizzazioni.
# Uso: bash tool/prepare.sh android|windows|macos
set -euo pipefail
PLATFORM="$1"

flutter --version
# "flutter create" non sovrascrive i file già presenti (manifest, MainActivity, entitlements).
flutter create --org com.sirjoe --project-name sirjoe_player --platforms="$PLATFORM" .
rm -rf test

case "$PLATFORM" in
  windows)
    sed -i 's/window.Create(L"sirjoe_player"/window.Create(L"SirJoe Player"/' windows/runner/main.cpp
    sed -i 's/Win32Window::Size size(1280, 720);/Win32Window::Size size(1100, 800);/' windows/runner/main.cpp
    ;;
  macos)
    sed -i '' 's/^PRODUCT_NAME = .*/PRODUCT_NAME = SirJoe Player/' macos/Runner/Configs/AppInfo.xcconfig
    PL=macos/Runner/Info.plist
    /usr/libexec/PlistBuddy -c "Add :NSBluetoothAlwaysUsageDescription string 'SirJoe Player usa il Bluetooth per collegarsi alle tue cuffie o casse.'" "$PL" || true
    /usr/libexec/PlistBuddy -c "Add :NSBluetoothPeripheralUsageDescription string 'SirJoe Player usa il Bluetooth per collegarsi alle tue cuffie o casse.'" "$PL" || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName 'SirJoe Player'" "$PL" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string 'SirJoe Player'" "$PL"
    ;;
  android)
    ;;
esac

flutter pub get
dart run flutter_launcher_icons || echo "Icone non generate (continuo)"
