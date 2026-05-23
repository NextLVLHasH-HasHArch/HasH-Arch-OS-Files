#!/usr/bin/env bash
#
# HasH Sweet lock screen - Qt6 / Plasma 6 installer.
#
# Backs up the current (Qt5, broken) Sweet lock-screen QML and installs the
# Qt6 port so Plasma 6 stops logging "Lockscreen QML outdated, falling back to
# default" and actually renders the HasH look.
#
# Does NOT touch the breeze package and does NOT change the wallpaper plugin
# (com.hash.matrixrain stays configured via kscreenlockerrc).
#
# Run as root:  sudo ./install.sh
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SRC_DIR/contents/lockscreen"

DEST_ROOT="/usr/share/plasma/look-and-feel/Sweet/contents"
DEST="$DEST_ROOT/lockscreen"

STAMP="$(date +%Y%m%d-%H%M%S)"

if [[ $EUID -ne 0 ]]; then
    echo "This script writes to /usr/share and must be run as root (sudo)." >&2
    exit 1
fi

if [[ ! -d "$SRC" ]]; then
    echo "Source dir not found: $SRC" >&2
    exit 1
fi

if [[ ! -d "$DEST_ROOT" ]]; then
    echo "Sweet look-and-feel not found at: $DEST_ROOT" >&2
    echo "Is the Sweet global theme installed?" >&2
    exit 1
fi

mkdir -p "$DEST"

# The QML files this port provides. Each existing file is backed up first.
FILES=(
    LockScreen.qml
    LockScreenUi.qml
    MainBlock.qml
    MediaControls.qml
    NoPasswordUnlock.qml
    PasswordSync.qml
    LockOsd.qml
    config.qml
    config.xml
    qmldir
)

echo "Installing HasH Qt6 Sweet lock screen into: $DEST"
for f in "${FILES[@]}"; do
    if [[ -f "$DEST/$f" ]]; then
        cp -a "$DEST/$f" "$DEST/$f.qt5-bak-$STAMP"
        echo "  backed up: $f -> $f.qt5-bak-$STAMP"
    fi
    install -m 0644 "$SRC/$f" "$DEST/$f"
    echo "  installed: $f"
done

echo
echo "Done. The Sweet lock screen is now the Qt6 port."
echo "Backups carry the suffix .qt5-bak-$STAMP"
echo
echo "To test without locking yourself out, run as your normal user:"
echo "  setsid -f /usr/lib/kscreenlocker_greet --testing"
echo "and confirm the journal no longer shows 'Lockscreen QML outdated'."
