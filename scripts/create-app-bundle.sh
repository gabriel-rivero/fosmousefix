#!/bin/bash
set -euo pipefail

# Creates MouseFix Preferences.app with the daemon bundled inside
# Usage: ./scripts/create-app-bundle.sh [build-dir]

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${1:-$REPO_DIR/.build/arm64-apple-macosx/release}"
APP_NAME="MouseFix Preferences.app"
APP_DIR="$REPO_DIR/$APP_NAME"

echo "Creating $APP_NAME ..."

# Build if needed (BUILD_DAEMON enables the MouseFix target for bundling)
if [ ! -x "$BUILD_DIR/MouseFix" ] || [ ! -x "$BUILD_DIR/Preferences" ]; then
  echo "Building MouseFix & Preferences..."
  (cd "$REPO_DIR" && BUILD_DAEMON=1 swift build -c release)
fi

# Remove old bundle
rm -rf "$APP_DIR"

# Create bundle structure
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binaries
cp "$BUILD_DIR/Preferences" "$APP_DIR/Contents/MacOS/Preferences"
cp "$BUILD_DIR/MouseFix" "$APP_DIR/Contents/Resources/daemon"
chmod 755 "$APP_DIR/Contents/MacOS/Preferences"
chmod 755 "$APP_DIR/Contents/Resources/daemon"

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Preferences</string>
    <key>CFBundleIdentifier</key>
    <string>com.mousefix.preferences</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MouseFix Preferences</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc sign to avoid macOS "damaged" errors on unsigned bundles
codesign --force --sign - --deep "$APP_DIR" 2>/dev/null || true

echo "✓ Created $APP_DIR"
echo ""
echo "  Drag $APP_NAME to /Applications to install."
echo "  Then open it and click Install Daemon."
echo ""
echo "  ⚠ If macOS blocks the app:"
echo "    • Right-click → Open (once, to bypass Gatekeeper)"
echo "    • Or run: xattr -cr /Applications/$APP_NAME"
