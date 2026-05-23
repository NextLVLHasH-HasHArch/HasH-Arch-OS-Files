#!/usr/bin/env bash
# Install HasH-Arch Settings into the user's session (no root).
#   - hash-settings        -> ~/.local/bin/hash-settings  (executable)
#   - hash-settings.desktop -> ~/.local/share/applications/
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin"
APPS="$HOME/.local/share/applications"

mkdir -p "$BIN" "$APPS"

install -m 0755 "$SRC/hash-settings" "$BIN/hash-settings"
install -m 0644 "$SRC/hash-settings.desktop" "$APPS/hash-settings.desktop"

# refresh the application database so the launcher entry shows up
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APPS" >/dev/null 2>&1 || true
fi

echo "Installed:"
echo "  $BIN/hash-settings"
echo "  $APPS/hash-settings.desktop"
echo "Run with:  hash-settings"
