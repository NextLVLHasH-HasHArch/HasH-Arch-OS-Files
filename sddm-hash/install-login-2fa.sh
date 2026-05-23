#!/usr/bin/env bash
# install-login-2fa.sh — deploy the HasH SDDM 2FA login fix (Bundle 1).
#
# What it does:
#   1. Backs up and installs the FIXED Login.qml (slide transition; fixes the
#      structural Connections bug that broke the greeter / dead login button).
#   2. Installs the restyled Input.qml (lock-screen colours).
#   3. Adds pam_google_authenticator to /etc/pam.d/sddm so PAM actually asks for
#      the code (this is what makes the password->code slide trigger).
#
# Does NOT touch the wallpaper, lock screen, or daemon (those are separate).
#
# !!! AUTH-CRITICAL: keep a TTY open (Ctrl+Alt+F2) and DO NOT log fully out
#     until you've verified login works. The fork daemon/greeter are already
#     installed; this only swaps theme QML + adds one PAM line (both backed up).
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "run with sudo: sudo $0"; exit 1; }

REPO="$(cd "$(dirname "$0")" && pwd)/hash-theme"
THEME=/usr/share/sddm/themes/Sweet-Qt6
PAM=/etc/pam.d/sddm
STAMP="$(date +%Y%m%d-%H%M%S)"

echo "== backing up + installing theme QML =="
install -Dm644 "$THEME/Login.qml"            "$THEME/Login.qml.bak-$STAMP"
install -Dm644 "$THEME/components/Input.qml"  "$THEME/components/Input.qml.bak-$STAMP"
install -Dm644 "$REPO/Login.qml"              "$THEME/Login.qml"
install -Dm644 "$REPO/Input.qml"              "$THEME/components/Input.qml"
echo "   Login.qml + Input.qml installed (backups: *.bak-$STAMP)"

echo "== enabling the verification-code PAM prompt =="
if grep -q pam_google_authenticator "$PAM"; then
    echo "   already present in $PAM — leaving as is"
else
    cp -a "$PAM" "$PAM.bak-$STAMP"
    # add GA right after the password stack so it runs AFTER the password check.
    # nullok = accounts without ~/.google_authenticator are not forced into 2FA.
    sed -i '0,/^auth\s\+include\s\+system-login/s//&\nauth        required    pam_google_authenticator.so nullok/' "$PAM"
    echo "   added 'auth required pam_google_authenticator.so nullok' (backup: $PAM.bak-$STAMP)"
fi

echo
echo "== DONE. Now test WITHOUT logging out: =="
echo "   - open a TTY first: Ctrl+Alt+F2 (login there has no 2FA = your recovery)"
echo "   - sudo systemctl restart sddm   (or switch-user) and try logging in"
echo "   - after the password, the field should SLIDE to the verification code"
echo "   To roll back: restore $THEME/Login.qml.bak-$STAMP and $PAM.bak-$STAMP"
