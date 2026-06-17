#!/bin/bash
#
# 打包 TouchBarTerminal.app 成可分發的版本。
#
# 用法：
#   ./scripts/build-release.sh
#
# 產出：
#   build/TouchBarTerminal.app   （Universal Binary，可直接執行）
#
# 進階（簽名 + notarization，需 Apple Developer 帳號）：
#   1. 在 Xcode 設定 Signing Team
#   2. 簽名：   codesign --deep --force --options runtime \
#                --sign "Developer ID Application: <你的名字>" \
#                build/TouchBarTerminal.app
#   3. 公證：   xcrun notarytool submit build/TouchBarTerminal.zip \
#                --apple-id <email> --team-id <TEAMID> --password <app-專用密碼> --wait
#   4. 裝訂：   xcrun stapler staple build/TouchBarTerminal.app

set -e

cd "$(dirname "$0")/.."

echo "🔧 產生 Xcode 專案..."
xcodegen generate

echo "🏗  Release build（Universal Binary）..."
xcodebuild \
  -project TouchBarTerminal.xcodeproj \
  -scheme TouchBarTerminal \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  ONLY_ACTIVE_ARCH=NO \
  build

APP_PATH=$(find build/DerivedData -name "TouchBarTerminal.app" -type d | head -1)

mkdir -p build
rm -rf build/TouchBarTerminal.app
cp -R "$APP_PATH" build/TouchBarTerminal.app

echo "✅ 完成：build/TouchBarTerminal.app"
echo "   架構：$(lipo -archs build/TouchBarTerminal.app/Contents/MacOS/TouchBarTerminal 2>/dev/null || echo '未知')"
echo ""
echo "未簽名的 app 第一次開啟時，使用者需在「系統設定 → 隱私權與安全性」按「強制打開」。"
