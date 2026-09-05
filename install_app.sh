#!/bin/bash
set -e

# ==============================================================================
# mic-homemade-mac - Build & Install macOS .app
# ==============================================================================

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="mic-homemade-mac"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DEST_APP="/Applications/$APP_NAME.app"

echo "🔨 1. กำลัง Compile โปรเจกต์ (Release mode)..."
cd "$PROJECT_DIR"
swift build -c release

echo "📦 2. กำลังสร้างโครงสร้าง $APP_NAME.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# คัดลอก Binary ตัวเต็มที่ compile เสร็จ
cp "$PROJECT_DIR/.build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# คัดลอก App Icon ถ้ามี
if [ -f "$PROJECT_DIR/mic-homemade-mac/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/mic-homemade-mac/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# สร้าง Info.plist สำหรับ macOS App Bundle
cat << 'EOF' > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>mic-homemade-mac</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.zeen.mic-homemade-mac</string>
    <key>CFBundleName</key>
    <string>mic-homemade-mac</string>
    <key>CFBundleDisplayName</key>
    <string>mic-homemade-mac</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>mic-homemade-mac needs microphone access to send your microphone audio to the selected Mac output.</string>
</dict>
</plist>
EOF

echo "🔏 3. กำลัง Sign Code พร้อม Entitlements (Microphone Permission)..."
codesign --force --deep --sign - --entitlements "$PROJECT_DIR/mic-homemade-mac/mic-homemade-mac.entitlements" "$APP_BUNDLE"

echo "🚀 4. กำลังติดตั้งลง /Applications..."
rm -rf "$DEST_APP"
cp -R "$APP_BUNDLE" "$DEST_APP"

# รีเฟรช LaunchServices เพื่อให้ macOS รู้จักแอปทันที
touch "$DEST_APP"

echo "✅ ติดตั้งสำเร็จเรียบร้อย!"
echo "👉 คุณสามารถเปิดใช้งานได้จาก Launchpad หรือพิมพ์ 'open -a mic-homemade-mac' ใน Terminal"
