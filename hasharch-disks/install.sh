#!/usr/bin/env bash
# Deploy HasH-Disks to the user's ~/.local locations.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
install -Dm755 "$here/hash-disks"        "$HOME/.local/bin/hash-disks"
install -Dm755 "$here/hash-disks-helper" "$HOME/.local/bin/hash-disks-helper"
install -Dm644 "$here/hash-disks.desktop" "$HOME/.local/share/applications/hash-disks.desktop"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
echo "Installed hash-disks, hash-disks-helper and the launcher entry."
