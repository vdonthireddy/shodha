#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==========================================="
echo "   Shodha Installer for macOS              "
echo "==========================================="

echo "==> Building fresh Shodha.app..."
"$DIR/build.sh"

# Determine target directory
if [ -w "/Applications" ]; then
    TARGET_DIR="/Applications"
else
    TARGET_DIR="$HOME/Applications"
fi
mkdir -p "$TARGET_DIR"

DEST="$TARGET_DIR/Shodha.app"

echo "==> Closing any running EchoBuddy or Shodha instances..."
pkill -x EchoBuddy 2>/dev/null || true
pkill -x Shodha 2>/dev/null || true
sleep 0.5

# Clean up legacy app if present
rm -rf "$TARGET_DIR/EchoBuddy.app"

echo "==> Installing to $DEST..."
rm -rf "$DEST"
cp -R "$DIR/Shodha.app" "$DEST"
chmod -R u+w "$DEST"

# Register new bundle with LaunchServices
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -u "$DEST" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$DEST" 2>/dev/null || true

# Remove quarantine attribute so Gatekeeper allows it cleanly
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "==> Launching Shodha..."
open "$DEST"

echo "==========================================="
echo " ✨ Shodha has been installed & launched!"
echo " Location: $DEST"
echo "==========================================="
