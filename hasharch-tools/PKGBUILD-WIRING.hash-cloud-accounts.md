# PKGBUILD wiring — hash-cloud-accounts (+ cloud / fingerprint installer features)

New files in this directory that the `hasharch-tools` package must install:

| Source (this dir)               | Installed path                                              | Mode |
|---------------------------------|-------------------------------------------------------------|------|
| `hash-cloud-accounts`           | `/usr/bin/hash-cloud-accounts`                              | 755  |
| `hash-cloud-accounts.desktop`   | `/etc/skel/.config/autostart/hash-cloud-accounts.desktop`  | 644  |

## PKGBUILD snippet (package_hasharch-tools)

```bash
# First-boot cloud-storage wizard
install -Dm755 "$srcdir/hash-cloud-accounts" \
    "$pkgdir/usr/bin/hash-cloud-accounts"

# Autostart-once entry: opens the wizard on first login only if no rclone remote
# exists yet, then deletes itself (handled inside the tool via --autostart).
# Shipped in /etc/skel so every new user gets it; mirrors hash-apply-theme.
install -Dm644 "$srcdir/hash-cloud-accounts.desktop" \
    "$pkgdir/etc/skel/.config/autostart/hash-cloud-accounts.desktop"
```

## Runtime dependencies

`hash-cloud-accounts` needs, at runtime (declare in `depends`/`optdepends`):

- `rclone`        — OAuth sign-in + FUSE mount engine (REQUIRED to add accounts)
- `fuse3`         — provides `fusermount3` for `rclone mount` (REQUIRED to mount)
- `python-pyqt6`  — the GUI toolkit
- `systemd`       — `systemctl --user` for the per-remote mount units (always present)

These are also pulled in by the Calamares **Cloud storage** packagechooser
(`packagechooser@cloud.conf`) when the user ticks any provider, so a fresh
install that selected cloud storage already has them. Ship them as `depends`
if `hasharch-tools` itself should always provide the wizard, or as `optdepends`
if it's meant to degrade to "install rclone first" (the tool already shows that
prompt and a Software-Center hint when rclone is missing).

## Calamares side (already wired in reproducible/calamares/)

- `modules/packagechooser@cloud.conf`     — installs cloud TOOLING (rclone, fuse3,
  hasharch-tools, kio-gdrive for Google) for ticked providers.
- `modules/packagechooser@biometric.conf` — installs `fprintd` + `libfprint` when
  "Fingerprint unlock" is ticked. Enrolment is done at first boot by the existing
  `hash-security` GUI (no extra wiring needed here).
- `settings.conf` — both choosers added to `instances:` and the `show:` sequence
  (after `packagechooser@browser`, before `summary`).

The `packages` exec module (already in the sequence) installs whatever the
choosers wrote to global storage; no contextualprocess is needed for either
(unlike the browser, nothing has to be *removed* afterwards).
