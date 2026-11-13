#!/bin/bash
set -e

APP_NAME="TimeWaster"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "🔨 Building ${APP_NAME}..."
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
swiftc -O \
    -target arm64-apple-macosx14.0 \
    -module-cache-path /tmp/swift-module-cache \
    -lsqlite3 \
    Sources/TimeWaster/*.swift \
    -o "${MACOS_DIR}/${APP_NAME}"

echo "📦 Packaging ${APP_BUNDLE}..."

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.TimeWaster2</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>TimeWaster Cap</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>TimeWaster needs permission to inspect the active tab URL in your browser and redirect distracting sites when your daily time cap is reached.</string>
</dict>
</plist>
EOF

codesign --force --deep --sign - "${APP_BUNDLE}"
echo "✅ Built ${APP_BUNDLE} successfully!"
