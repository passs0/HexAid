#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="HexAid"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
ICONSET_DIR="${BUILD_DIR}/AppIcon.iconset"

echo "1. Generating Apple Liquid Glass icon..."
mkdir -p "${BUILD_DIR}"
swift -module-cache-path /tmp/clang-module-cache scripts/generate_icon.swift "${ICONSET_DIR}" "assets/icon.png"

mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
iconutil -c icns "${ICONSET_DIR}" -o "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

echo "2. Writing Info.plist..."
cat > "${APP_BUNDLE}/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>HexAid</string>
    <key>CFBundleIdentifier</key>
    <string>com.hexaid.app</string>
    <key>CFBundleName</key>
    <string>HexAid</string>
    <key>CFBundleDisplayName</key>
    <string>HexAid</string>
    <key>CFBundleVersion</key>
    <string>2.3.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.3</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>HexAid</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

if [ -d "assets/HexAid.icon.xcassets" ]; then
    if xcrun --find actool >/dev/null 2>&1; then
        echo "🎨 Compiling the Light, Dark, Clear, and Tinted app icon variants..."
        PARTIAL_PLIST="$(mktemp "${APP_BUNDLE}/icon-partial.XXXXXX")"
        xcrun actool "assets/HexAid.icon.xcassets" \
            --compile "${APP_BUNDLE}/Contents/Resources" \
            --platform macosx \
            --minimum-deployment-target 15.0 \
            --app-icon HexAid \
            --output-partial-info-plist "$PARTIAL_PLIST" \
            --output-format human-readable-text
        python3 - "$PARTIAL_PLIST" "${APP_BUNDLE}/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    additions = plistlib.load(f)
with open(sys.argv[2], "rb") as f:
    info = plistlib.load(f)
info.update(additions)
with open(sys.argv[2], "wb") as f:
    plistlib.dump(info, f)
PY
        rm -f "$PARTIAL_PLIST"
    elif [ "${CI:-}" = "true" ]; then
        echo "Error: Xcode with actool is required to build the dynamic app icon." >&2
        exit 1
    else
        echo "Warning: actool is unavailable; using the legacy static icon for this local build." >&2
    fi
fi

echo "3. Compiling ${APP_NAME} (targeting arm64-apple-macos15.0)..."
swiftc -O \
    -target arm64-apple-macos15.0 \
    -module-cache-path /tmp/clang-module-cache \
    Sources/main.swift \
    -o "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" \
    -framework SwiftUI \
    -framework AppKit

echo "4. Signing ${APP_BUNDLE}..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "✅ Built ${APP_BUNDLE} successfully!"
echo "To install to /Applications:"
echo "  cp -R \"${APP_BUNDLE}\" /Applications/"
