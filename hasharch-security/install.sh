#!/usr/bin/env bash
# Deploy HasH-Security to the user's ~/.local locations.
# The GUI runs as the user; the helper is invoked only via pkexec at runtime.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
install -Dm755 "$here/hash-security"        "$HOME/.local/bin/hash-security"
install -Dm755 "$here/hash-security-helper" "$HOME/.local/bin/hash-security-helper"
install -Dm644 "$here/hash-security.desktop" "$HOME/.local/share/applications/hash-security.desktop"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
echo "Installed hash-security, hash-security-helper and the launcher entry."
echo
echo "NOTE: hash-security-helper performs privileged PAM edits and is run only"
echo "via pkexec by the GUI. For a system install with a polkit action, place"
echo "the helper in /usr/lib/hash-security/ and ship a polkit policy; the"
echo "user-local install above is sufficient for pkexec prompting."
