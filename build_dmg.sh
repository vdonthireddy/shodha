#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$DIR/dist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$DIR/Resources/Info.plist" 2>/dev/null || echo "1.0.0")
DMG_NAME="Shodha-${VERSION}-universal.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

echo "==========================================="
echo "   Shodha DMG Packager (Universal macOS)   "
echo "==========================================="

"$DIR/build.sh" --universal --dist

echo "==> Verifying universal binary & code signature..."
lipo -info "$DIR/Shodha.app/Contents/MacOS/Shodha"
codesign --verify --deep --strict "$DIR/Shodha.app"

STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT

cp -R "$DIR/Shodha.app" "$STAGING_DIR/Shodha.app"
ln -s /Applications "$STAGING_DIR/Applications"

cat > "$STAGING_DIR/HOW_TO_INSTALL.txt" <<'EOF'
Shodha Installation Guide
=========================

1. Drag "Shodha.app" onto the "Applications" folder icon right next to it.

2. First Launch (macOS Gatekeeper):
   Because Shodha is open-source and ad-hoc signed (not notarized with a paid
   Apple Developer ID), macOS may say "Shodha cannot be opened" or "unidentified
   developer" on first launch. To allow it:
     Option A: Control-click (or Right-click) Shodha in /Applications -> Open -> Open.
     Option B: Or go to System Settings -> Privacy & Security -> click "Open Anyway".
     Option C: Or run in Terminal:
               xattr -dr com.apple.quarantine /Applications/Shodha.app

3. Prerequisites for Full Features:
   - Local AI (Ollama): Install from https://ollama.com and pull a model, e.g.:
       ollama pull mistral
     (Or configure any OpenAI-compatible endpoint & API key in Shodha Settings.)
   - Built-in Tools (Reminders, Web Search, Notes, Calculator):
     Requires Python 3 (Xcode Command Line Tools: `xcode-select --install`,
     or Homebrew `brew install python`).

4. Shortcut:
   Press Option + Space anywhere to show or hide Shodha!
EOF

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

echo "==> Creating compressed DMG at $DMG_PATH..."
hdiutil create \
    -volname "Shodha" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

echo "==========================================="
echo " ✨ DMG created successfully!"
echo " File: $DMG_PATH"
echo " Size: $(du -h "$DMG_PATH" | awk '{print $1}')"
echo "==========================================="
