# HasH-Security

A dark/rounded PyQt6 settings app for HasH-Arch that turns on and enrolls the
custom auth methods — **Password, PIN, TOTP 2FA, Face (Howdy), Fingerprint
(fprintd)** — and chooses **where each applies** (Login / Lock / Sudo), without
ever editing PAM by hand.

The landing view is a Windows-Hello-style **Sign-in options** page: one card per
method showing its status (enrolled / available / no hardware / not installed)
with a primary action (Set up / Re-enroll / Remove / Install) and per-surface
(Login / Lock / Sudo) toggles. A **Matrix** page keeps the full methods × surface
grid, and there are detail pages for Face, Fingerprint, Two-Factor, PIN and a
**Policy & recovery** page (method order, faillock reset, TTY-fallback guidance).

## Components

| File | Runs as | Role |
|------|---------|------|
| `hash-security` | the user | GUI; read-only state detection; drives enrollment; calls the helper via `pkexec` for privileged edits. **Never run as root.** |
| `hash-security-helper` | root (via `pkexec` only) | All privileged PAM edits: atomic, backed-up, validated, idempotent. |
| `test-pam.py` | the user | Dry-run test of the helper's PAM logic on `/tmp` copies. Never touches real `/etc/pam.d`. |
| `hash-security.desktop` | — | Launcher / System Settings entry. |
| `install.sh` | the user | Deploys to `~/.local`. |

## Surfaces → PAM files

| Surface | File |
|---------|------|
| Login | `/etc/pam.d/sddm` |
| Lock | `/etc/pam.d/kde` |
| Sudo | `/etc/pam.d/sudo` |
| **(TTY login)** | `/etc/pam.d/login` — **NEVER edited.** Password-only recovery path. |

## PAM auth model the helper writes (per surface)

Only the lines for **enabled** methods are emitted, each tagged `# hash-security`
and merged around the existing password include:

```
auth  required   pam_faillock.so preauth          # hash-security
auth  sufficient pam_howdy.so                      # hash-security  (face, if enabled)
auth  sufficient pam_fprintd.so                    # hash-security  (fingerprint, if enabled)
auth  include    system-login                      # (untouched) -> pam_unix = password
auth  required   pam_google_authenticator.so nullok # hash-security (TOTP, if enabled)
auth  required   pam_faillock.so authfail          # hash-security
```

- Biometrics are `sufficient` (short-circuit on success).
- The password include is **always kept below** them — password is always a
  working fallback.
- TOTP is layered **after** the password line.
- faillock brackets the stack only when at least one managed method is active.

## Safety (non-negotiable, enforced in code)

- Timestamped backup of every file before any write
  (`/etc/pam.d/<svc>.hash-bak-<ts>`).
- The helper **refuses** to touch `login` / `system-*` (the TTY recovery path).
- The helper **refuses** to write any stack that lost the password fallback.
- Edits are atomic (temp + validate + `os.replace`) and idempotent (markers).
- `restore <surface>` rolls back to the latest backup.

Run the safety test as a normal user:

```
python3 test-pam.py
```

## Install

```
./install.sh
```

For a full system install with a polkit action (no per-call password if policy
allows), ship `hash-security-helper` under `/usr/lib/hash-security/` plus a
polkit `.policy` for the `org.hasharch.security.pam-edit` action.

## Privileged subcommands (helper, via `pkexec`)

Beyond the PAM `enable` / `disable` / `restore` edits, the helper also wraps a
few upstream tools. **None of these touch any PAM file** — enabling a method in
the auth stack stays a separate, explicit PAM toggle:

| Subcommand | Action |
|------------|--------|
| `install howdy\|fprintd` | Install from official repos (pacman) or the detected AUR helper (`yay`/`paru`). Allow-listed: anything else is refused. AUR builds drop to `$SUDO_USER`. |
| `howdy-add\|howdy-clear <user>` | `howdy add` / `howdy clear` for face enrollment. |
| `howdy-config <key> <value>` | Set Howdy `certainty` / `dark_threshold` (allow-listed + range-validated). |
| `fprint-enroll <user> [finger]` / `fprint-delete <user>` | `fprintd-enroll` / `fprintd-delete`. |
| `faillock-reset <user>` | `faillock --user <user> --reset`. |

## Phasing

- **P1 — complete:** page shell, Overview/Matrix (methods × surfaces with
  toggles + status chips), TOTP management (enable / Set up with QR + secret +
  scratch codes via `google-authenticator` / remove).
- **P2 — complete:** Sign-in-options chooser; Face (Howdy) and Fingerprint
  (fprintd) detect hardware, hide cleanly when absent, offer install (Howdy via
  AUR, fprintd via repos), and run live enrollment / clear / sensitivity through
  the helper via `pkexec`. Per-surface toggles drive the PAM helper.
- **P3 — Policy/recovery done; PIN is detect+explain:** Policy & recovery page
  (method order, faillock reset, TTY-fallback + test-first guidance). PIN remains
  **intentionally not enabled** — the helper refuses to write an untested PIN
  auth path (lockout safety). System Settings KCM still future work.
