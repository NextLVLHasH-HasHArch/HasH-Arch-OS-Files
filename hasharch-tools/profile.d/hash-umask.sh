# Installed to /etc/profile.d/hash-umask.sh
# HasH default: everything a user creates is user-only (files 600, dirs 700).
# Pairs with UMASK 077 + HOME_MODE 0700 in /etc/login.defs (set at install) so
# graphical (PAM/pam_umask) and shell sessions both default to user-only.
# NOTE: this (and 0700 homes) stops OTHER non-root users from reading your files.
# It does NOT stop root — blocking root requires per-user ENCRYPTION (see the
# keystore / per-user-encryption plan), since root bypasses file permissions.
umask 077
