#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$DIR/Shodha.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Preparing Shodha.app bundle structure..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "==> Compiling Swift sources..."
swiftc -O \
    -parse-as-library \
    "$DIR/Sources/State/SpeechManager.swift" \
    "$DIR/Sources/State/MCPClient.swift" \
    "$DIR/Sources/State/ReminderManager.swift" \
    "$DIR/Sources/State/OllamaAgent.swift" \
    "$DIR/Sources/State/AppState.swift" \
    "$DIR/Sources/Views/CuteMascotView.swift" \
    "$DIR/Sources/Views/AvatarView.swift" \
    "$DIR/Sources/Views/SpeechDialogView.swift" \
    "$DIR/Sources/Windows/FloatingAvatarPanel.swift" \
    "$DIR/Sources/Windows/SpeechDialogPanel.swift" \
    "$DIR/Sources/Windows/MenuBarManager.swift" \
    "$DIR/Sources/Main.swift" \
    -o "$MACOS_DIR/Shodha"

echo "==> Copying Resources and Info.plist..."
cp "$DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
if [ -f "$DIR/Resources/AppIcon.icns" ]; then
    cp "$DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
    cp "$DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon_default.icns"
fi
CURRENT_AVATAR="$HOME/Library/Application Support/Shodha/current_avatar.png"
if [ ! -f "$CURRENT_AVATAR" ]; then
    CURRENT_AVATAR="$HOME/Library/Application Support/EchoBuddy/current_avatar.png"
fi
if [ -f "$CURRENT_AVATAR" ]; then
    ICONSET=$(mktemp -d)/icon.iconset
    mkdir -p "$ICONSET"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$CURRENT_AVATAR" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null 2>&1 || true
        s2=$((s * 2))
        sips -z $s2 $s2 "$CURRENT_AVATAR" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null 2>&1 || true
    done
    iconutil -c icns "$ICONSET" -o "$RESOURCES_DIR/AppIcon.icns" 2>/dev/null || true
    rm -rf "$(dirname "$ICONSET")"
fi
chmod -R u+w "$APP_DIR"
if [ -f "$DIR/Resources/default_mascot.png" ]; then
    cp "$DIR/Resources/default_mascot.png" "$RESOURCES_DIR/default_mascot.png"
fi
if [ -f "$DIR/Resources/mcp_scheduler_server.py" ]; then
    cp "$DIR/Resources/mcp_scheduler_server.py" "$RESOURCES_DIR/mcp_scheduler_server.py"
    chmod +x "$RESOURCES_DIR/mcp_scheduler_server.py"
fi

echo "==> Ad-hoc code signing..."
codesign --force --deep --sign - "$APP_DIR"

echo "==> Successfully built $APP_DIR"
