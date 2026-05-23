#!/usr/bin/env bash
# install-hash-desktop.sh — deploy the HasH-Arch login + lock + wallpaper changes.
#
# Installs (all backed up, all reversible):
#   1. SDDM Sweet-Qt6 theme  : Login.qml (2FA slide), Input.qml (restyle),
#      Main.qml (primary-display-only + GPU weather from /var/lib/hash),
#      components/WeatherScene.qml + weather.frag.qsb (GPU real-moon shader).
#   2. Sweet lock screen     : MainBlock.qml + LockScreenUi.qml (2FA slide).
#   3. /var/lib/hash          : shared dir the greeter reads weather.json from
#      (owned by you so hash-weather-sync can write it).
#   4. PAM                    : pam_google_authenticator on /etc/pam.d/sddm and
#      /etc/pam.d/kde (lock screen) — nullok, password always first.
#
# !!! AUTH-CRITICAL. Before testing: open a TTY (Ctrl+Alt+F2) — that login has no
#     2FA and is your recovery path. Don't log fully out until login+lock verified.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo: sudo $0"; exit 1; }

USER_NAME="${SUDO_USER:-$(logname 2>/dev/null || echo hash)}"
REPO="$(cd "$(dirname "$0")" && pwd)"
THEME=/usr/share/sddm/themes/Sweet-Qt6
LOCK=/usr/share/plasma/look-and-feel/Sweet/contents/lockscreen
STAMP="$(date +%Y%m%d-%H%M%S)"
bk() { [ -e "$1" ] && cp -a "$1" "$1.hash-bak-$STAMP" || true; }

echo "== [1/4] SDDM Sweet-Qt6 theme =="
for f in Login.qml Input.qml Main.qml WeatherScene.qml weather.frag.qsb; do
    case "$f" in
        Input.qml|WeatherScene.qml|weather.frag.qsb) dst="$THEME/components/$f" ;;
        *) dst="$THEME/$f" ;;
    esac
    bk "$dst"
    install -Dm644 "$REPO/hash-theme/$f" "$dst"
    echo "   installed $dst"
done

# Lock-screen 2FA is OPT-IN: pass --with-lock-2fa. It is OFF by default because
# the kscreenlocker QML auth flow needs live testing on this Plasma version; the
# default install leaves your working (password) lock screen untouched.
WITH_LOCK_2FA=""
[ "${1:-}" = "--with-lock-2fa" ] && WITH_LOCK_2FA=1
if [ -n "$WITH_LOCK_2FA" ]; then
    echo "== [2/4] Sweet lock screen 2FA (opt-in) =="
    for f in MainBlock.qml LockScreenUi.qml; do
        bk "$LOCK/$f"
        install -Dm644 "$REPO/hash-lockscreen/$f" "$LOCK/$f"
        echo "   installed $LOCK/$f"
    done
else
    echo "== [2/4] Sweet lock screen — SKIPPED (pass --with-lock-2fa to enable) =="
fi

echo "== [3/4] /var/lib/hash (shared weather file dir, owned by $USER_NAME) =="
install -d -m 755 -o "$USER_NAME" -g "$USER_NAME" /var/lib/hash
echo "   /var/lib/hash ready"
# populate it now from the user's desktop config (best effort, runs as the user)
if command -v runuser >/dev/null; then
    runuser -u "$USER_NAME" -- bash -lc 'hash-weather-sync.sh' 2>/dev/null \
        && echo "   weather.json populated" \
        || echo "   (run 'hash-weather-sync.sh' in your session to populate weather.json)"
fi

echo "== [4/4] PAM — verification-code prompt on login + lock =="
# /etc/pam.d/sddm : add GA after the system-login auth include
PAM_SDDM=/etc/pam.d/sddm
if grep -q pam_google_authenticator "$PAM_SDDM"; then
    echo "   sddm: GA already present"
else
    bk "$PAM_SDDM"
    sed -i '0,/^auth\s\+include\s\+system-login/s//&\nauth        required    pam_google_authenticator.so nullok/' "$PAM_SDDM"
    echo "   sddm: added GA (backup $PAM_SDDM.hash-bak-$STAMP)"
fi
# /etc/pam.d/kde : the lock screen. Only touched with --with-lock-2fa, since the
# lock QML must be able to answer the code prompt or unlock will fail. Without the
# flag we REMOVE any GA line we previously added so the lock stays password-only
# and working.
PAM_KDE=/etc/pam.d/kde
if [ -n "$WITH_LOCK_2FA" ]; then
    if [ -e "$PAM_KDE" ] && grep -q pam_google_authenticator "$PAM_KDE"; then
        echo "   kde: GA already present"
    else
        bk "$PAM_KDE"
        base=/usr/lib/pam.d/kde; [ -e "$PAM_KDE" ] && base="$PAM_KDE"
        sed '0,/^auth\s\+include\s\+system-local-login/s//&\nauth       required                    pam_google_authenticator.so nullok/' \
            "$base" > "$PAM_KDE"
        echo "   kde: wrote $PAM_KDE with GA (lock screen 2FA)"
    fi
elif [ -e "$PAM_KDE" ] && grep -q pam_google_authenticator "$PAM_KDE"; then
    # ensure the lock is NOT left requiring a code it can't answer
    bk "$PAM_KDE"; rm -f "$PAM_KDE"
    echo "   kde: removed /etc/pam.d/kde (fall back to stock password-only lock)"
else
    echo "   kde: left untouched (password-only lock)"
fi

echo
echo "== DONE. TEST CAREFULLY (keep Ctrl+Alt+F2 TTY open): =="
echo "   login : sudo systemctl restart sddm  -> password slides to code (2FA works)"
if [ -n "$WITH_LOCK_2FA" ]; then
echo "   lock  : Meta+L  -> password slides to code  (EXPERIMENTAL; reboot recovers)"
else
echo "   lock  : password-only (working). Lock 2FA is opt-in: re-run with --with-lock-2fa"
fi
echo "   Revert: restore the *.hash-bak-$STAMP files, then restart sddm."
