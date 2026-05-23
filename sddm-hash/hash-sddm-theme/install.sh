#!/usr/bin/env bash
# install.sh — install the HasH SDDM theme and make it the active greeter theme.
#
# Run with root (the theme dir and /etc/sddm.conf.d are root-owned):
#     sudo ./install.sh
#
# What it does:
#   1. copies this theme dir to /usr/share/sddm/themes/hash/
#   2. backs up then sets [Theme] Current=hash in
#      /etc/sddm.conf.d/kde_settings.conf
#
# It does NOT touch the lock screen and does NOT restart SDDM (log out / reboot
# to see it). /var/lib/hash/weather.json is provided by the HasH desktop bundle.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="/usr/share/sddm/themes/hash"
CONF_DIR="/etc/sddm.conf.d"
CONF="$CONF_DIR/kde_settings.conf"
STAMP="$(date +%Y%m%d-%H%M%S)"

if [[ $EUID -ne 0 ]]; then
    echo "error: run as root (sudo ./install.sh)" >&2
    exit 1
fi

echo "==> Installing theme to $DEST"
mkdir -p "$DEST"
# Copy theme files (exclude the installer and editor backups).
rsync -a --delete \
    --exclude 'install.sh' \
    --exclude '*.bak' \
    --exclude '*.hash-bak-*' \
    "$SRC"/ "$DEST"/ 2>/dev/null || {
        # rsync not available -> plain cp
        rm -rf "$DEST"
        mkdir -p "$DEST"
        cp -a "$SRC"/. "$DEST"/
        rm -f "$DEST/install.sh"
    }

echo "==> Configuring $CONF"
mkdir -p "$CONF_DIR"
if [[ -f "$CONF" ]]; then
    cp -a "$CONF" "$CONF.hash-bak-$STAMP"
    echo "    backed up existing config to $CONF.hash-bak-$STAMP"
fi

# Set [Theme] Current=hash, preserving the rest of the file.
python3 - "$CONF" <<'PY'
import configparser, sys, os
path = sys.argv[1]
cp = configparser.ConfigParser()
cp.optionxform = str  # preserve key case
if os.path.exists(path):
    cp.read(path)
if not cp.has_section("Theme"):
    cp.add_section("Theme")
cp.set("Theme", "Current", "hash")
with open(path, "w") as f:
    cp.write(f, space_around_delimiters=False)
PY

echo "==> Done. Active SDDM theme is now 'hash'."
echo "    Log out or reboot to see the HasH greeter."
echo "    Revert with: sudo cp \"$CONF.hash-bak-$STAMP\" \"$CONF\"  (if a backup was made)"
