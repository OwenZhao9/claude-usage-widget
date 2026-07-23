#!/bin/bash
# 编译 release 二进制并组装成 .app（含 ad-hoc 签名，稳定 Keychain 访问）。
set -euo pipefail
cd "$(dirname "$0")"

APP="Claude 额度.app"
BIN_NAME="ClaudeUsageWidget"

echo "▸ 编译 release…"
swift build -c release --product "$BIN_NAME"
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "▸ 组装 $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$BIN_NAME" "$APP/Contents/MacOS/$BIN_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "▸ ad-hoc 签名…"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "  （签名跳过）"

echo "✅ 完成：$APP"
echo "   启动：open \"$APP\"    或双击"
