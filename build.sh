#!/bin/bash
# 构建 动漫记录本.app
set -e
cd "$(dirname "$0")"

APP_NAME="动漫记录本"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

echo "▸ 编译 Swift 源码…"
# 部署目标 26.0：Liquid Glass（glassEffect / Glass）自 macOS 26 起提供
swiftc -O \
  -target arm64-apple-macosx26.0 \
  -o "$MACOS_DIR/$APP_NAME" \
  Sources/*.swift

echo "▸ 复制资源…"
cp Resources_seed.json "$RES_DIR/seed.json"
cp catalog.json "$RES_DIR/catalog.json"
cp Resources/Icon.icns "$RES_DIR/Icon.icns" 2>/dev/null || true

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>动漫记录本</string>
    <key>CFBundleDisplayName</key>
    <string>动漫记录本</string>
    <key>CFBundleExecutable</key>
    <string>动漫记录本</string>
    <key>CFBundleIdentifier</key>
    <string>com.lgalajj.animetracker</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>Icon</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>本地番剧观看记录本</string>
</dict>
</plist>
PLIST

echo "▸ 签名（ad-hoc）…"
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || echo "  （跳过签名）"

echo "✓ 构建完成：$APP_DIR"