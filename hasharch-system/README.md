# hasharch-system

HasH-Arch system glue: systemd user units (cava feed, weather sync, OBS tray, All-Apps watcher), cava config, KIO service menus, docs + the SDDM 2FA patch.

Part of **HasH-Arch** — a customised KDE Plasma 6 desktop (BlackArch/Arch fork)
maintained by NextLVLHasH & Opus 4.7.

## Install
Copy the contents into the matching location on a Plasma 6 system:
- `/home/hash/.config/systemd/user/cava-wallpaper.service`
- `/home/hash/.config/systemd/user/cava-wallpaper.timer`
- `/home/hash/.config/systemd/user/hash-weather-sync.service`
- `/home/hash/.config/systemd/user/hash-weather-sync.timer`
- `/home/hash/.config/systemd/user/hash-obs-tray.service`
- `/home/hash/.config/systemd/user/hash-obs-tray.path`
- `/home/hash/.config/systemd/user/hash-allapps.service`
- `/home/hash/.config/systemd/user/hash-allapps.path`
- `/home/hash/.config/cava/wallpaper.conf`
- `/home/hash/.local/share/kio/servicemenus/open-with-vscode.desktop`
- `/home/hash/Documents/HasH/HasH-Arch.md`
- `/home/hash/Documents/HasH/SDDM-2FA-popup-patch.md`
