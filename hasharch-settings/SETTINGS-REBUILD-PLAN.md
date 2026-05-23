# HasH Settings — full rebuild plan: a Windows 11 Settings clone over Linux, native

**User intent (consolidated):**
- *Map the **entire system** like KDE Plasma System Settings, but **better**.*
- ***Look like** and **work like** the Windows 11 Settings app.*
- Fully **native HasH UI** — **no `kcmshell6` / `systemsettings` / KDE popups**; just drive
  the **real backends** (kwriteconfig6, timedatectl, nmcli, systemctl, pacman …).
- **Custom HasH icons** for every category — "the lot", zero blanks.
- The **Apps** category is where the **uninstaller, store, default apps & startup apps**
  wire in (like Win11 *Apps*).
- Show the **exact command** for each action (learnable + scriptable for AI agents).

The box exposes **94 KDE modules** (`kcmshell6 --list`); every one lands somewhere below.

---

## 1. Look & work like Windows 11 Settings (the chrome)

Win11 Settings IA, rendered in the HasH dark/brand skin:

```
┌───────────────────────────────────────────────────────────┐
│  [#]  HasH Settings           ⌕ Search settings…           │  ← top: brand + global search
├───────────────┬───────────────────────────────────────────┤
│ ⬡ <user>      │  System ›                                  │  ← breadcrumb (clickable)
│   account hdr │  ┌─────────────────────────────────────┐   │
│               │  │ 🖥  Display                       ›  │   │  ← drill-in card row (chevron)
│ □ System      │  │ 🔊  Sound                  [▮▮▮▯]   │   │  ← inline control row
│ □ Devices     │  │ 🔔  Notifications            (on) ›  │   │
│ □ Network     │  └─────────────────────────────────────┘   │
│ □ Personalise │  ┌─────────────────────────────────────┐   │
│ □ Apps        │  │ 🔋  Power & battery               ›  │   │
│ □ Accounts    │  └─────────────────────────────────────┘   │
│ □ Time & lang │                                            │
│ □ Gaming      │                                            │
│ □ Access      │                                            │
│ □ Privacy/Sec │                                            │
│ □ Update      │                                            │
│ □ Admin       │                                            │
└───────────────┴───────────────────────────────────────────┘
```

**Behaviour to match Win11:**
- **Left category rail** with an account header on top; **global search** at the very top
  that jumps to any setting (uses the registry index — better than Plasma's per-KCM search).
- **Main pane = cards of rows.** Two row types: **drill-in** (chevron `›` → pushes a
  sub-page) and **inline control** (toggle / dropdown / slider right-aligned).
- **Breadcrumb + Back** navigation (System › Display › Advanced), nav stack.
- Rounded cards, hover highlight, section subheads — the Win11 "expander/list" feel, but
  `card_qss`/`Toggle`/ACCENT from our existing style (optionally re-skinned to brand
  magenta→green — see §7 open question).
- Reuse `BasePage`; add a `NavStack` + `Win11Row` (drill/inline) widget + `Breadcrumb`.

---

## 2. Category structure (Win11 top-level → our 94 modules)

| Win11 category (HasH) | Icon | Contains (modules → backend) |
|---|---|---|
| **System** | hash-system | Display(kscreen), Sound(pulseaudio), Notifications, Power&battery(powerdevil), Storage(hash-disks), Multitasking(kwinoptions/virtualdesktops), About+**Device specs**(sysinfo hub: cpu/mem/pci/gpu/sensors), Recovery/Troubleshoot(journal+systemd) |
| **Bluetooth & devices** | hash-devices | Bluetooth, Printers&scanners(cups), Mouse, Touchpad, Pen/Tablet, USB(info), Thunderbolt(bolt), AutoPlay(automounter), Solid actions |
| **Network & internet** | hash-network | Wi-Fi, Ethernet(networkmanagement), VPN, Mobile hotspot, Cellular, Proxy, Firewall, net prefs, interface info |
| **Personalisation** | hash-personalise | Background(wallpaper), Colours, Themes(lookandfeel), Lock screen(screenlocker), Fonts(+install), Plasma style, Window decorations, Cursors, Splash, Animations, Desktop effects, Screen edges, Virtual desktops, Taskbar/Start tweaks |
| **Apps** | hash-apps | **Installed apps→uninstall**, **Default apps**, **Startup apps**, **Get apps(Store)**, Optional features, File associations *(detail in §3)* |
| **Accounts** | hash-accounts | Your info, Email & accounts(kaccounts/HasH Accounts), **Sign-in options**(HasH Security: password/PIN/TOTP/fingerprint), Other users(users) |
| **Time & language** | hash-region | Date & time(timedatectl), Language & region(localectl), Typing/Spell(spellchecking), Keyboard layout |
| **Gaming** | hash-gaming | Game controllers(gamecontroller) |
| **Accessibility** | hash-access | Vision/Hearing/Interaction(access), virtual keyboard |
| **Privacy & security** | hash-privacy | HasH Security, Firewall, App permissions, Activity history(recentFiles), Search indexing(baloo), Firmware security |
| **System Update** | hash-update | Updates(hash-store --updates / pacman), update behaviour, keyring self-heal |
| **Administration** *(HasH bonus for Win sysadmins)* | hash-admin | Services(services.msc→systemctl), Event Viewer(eventvwr→journalctl), Users & Groups(lusrmgr→useradd/gpasswd), Background services(kded), Session(smserver), Login screen(SDDM), Boot splash(Plymouth) |

Read-only info modules (cpu/mem/pci/usb/gpu/glx/egl/vulkan/opencl/xserver/wayland/
sensors/edid/energy/interrupts/audio_information/kwinsupportinfo/firmware_security) →
fold into **System › Device specs** + **Administration** info cards.

---

## 3. Apps category — uninstaller & friends (your specific ask)

Mirrors Win11 **Apps**:
- **Installed apps** — searchable list (`pacman -Qe`/`-Qm` + size via `pacman -Qi`; flatpaks
  too). Each row: name, version, size, source badge (repo/AUR/flatpak), **⋯ → Uninstall**.
  Uninstall hands off to **hash-uninstaller** (maps a program + ALL its files) or does an
  inline `pkexec pacman -Rns` with the command shown. Sort by size/name/date.
- **Default apps** — Browser / Email / Terminal / File manager / Image / Video / Audio,
  set via `xdg-settings` + `kwriteconfig6` mimeapps (componentchooser backend). Per-type
  picker from installed `.desktop`s.
- **Startup apps** — toggle list of `~/.config/autostart` + `/etc/xdg/autostart` entries
  (autostart backend); add/remove; shows impact.
- **Get apps / Software** — opens **HasH App Manager (hash-store)** (Store).
- **File associations** — per-extension/MIME default app (filetypes backend, mimeapps.list).
- **Optional features** — curated BlackArch/extra tool groups (ties to the installer's
  packagechooser groups) — install/remove with one toggle.

---

## 4. Architecture — declarative engine (makes 94 modules tractable + scriptable)

Each setting is **data**, rendered by one generic page:
- `Setting(key, name, icon, control, backend, apply=…, detail=[…])` where `control ∈
  {toggle, combo, slider, text, action, drill}` and `backend ∈`:
  - `KConfig(file, group, key, type)` → `kreadconfig6/kwriteconfig6` (most Appearance/
    Workspace/Window/Notifications/Shortcuts).
  - `Cmd(read=[argv], write=[argv], priv)` → tools (timedatectl/localectl/nmcli/wpctl/
    kscreen-doctor/powerprofilesctl/lpadmin/boltctl/balooctl…); `priv`→`pkexec`.
  - `Info(cmd)` → read-only display.
- `apply` hooks: `kwin_reconfigure` (`qdbus org.kde.KWin /KWin reconfigure`),
  `plasma-apply-*`, `systemctl`, threaded `mkinitcpio`.
- `drill` rows push a sub-schema (Win11 hierarchy).
- Falls out for free: `hash-settings get/set <key>` **CLI** (AI-agent scriptable) + global
  search index. New setting = one data row.

---

## 5. Custom icons — "the lot"
Bespoke HasH icon per **category** (≈12) + key sub-pages, brand magenta→green gradient
(same recolour method as the app set), saved `hash-<cat>` in `hicolor`+`HasH-Icons`.
Win11-style flat line glyphs. Rendered to a sheet for sign-off. Zero blank icons = exit
criterion.

---

## 6. Remove (KDE machinery) & no popups
Delete `KCMPage/KCMHostPage/EmbeddedKCM`, X11 reparent, `kcm_list/launchable/icon/
module_exists/argv`, `find_kcm_window`, `open_kcm/open_module`, `PRIVILEGED_KCMS`,
`HAS_SYSTEMSETTINGS/HAS_KCMSHELL/KCMSHELL`, `"kde"` section, `_populate_sysmods`. No
`kcmshell6`/`systemsettings`. `QMessageBox` → `HasHDialog` (frameless, card_qss). Long ops
threaded with CliConsole progress.

---

## 7. Open question for you (before I build)
**Accent:** keep hash-settings' current **cyan `#56c5d8`**, or re-skin the whole app to the
**HasH brand magenta→green** to match the new logo/icons? (Win11 itself uses a single
accent; I'd lean brand magenta→green for consistency.)

---

## 8. Phasing (each phase: ast.parse + launch-smoke + per-category test + deploy to ~/.local/bin)
1. **Engine + Win11 chrome**: `Setting/KConfig/Cmd/Info`, `SchemaPage`, `NavStack`,
   `Win11Row`, `Breadcrumb`, global search, `get/set` CLI. Strip KCM machinery.
2. **Custom category icons** (≈12) → sheet → sign-off → install.
3. **System** (Display/Sound/Notifications/Power/Storage/Multitasking/About+specs).
4. **Personalisation** (the big KConfig set).
5. **Apps** (installed+uninstall, defaults, startup, store, associations, optional features).
6. **Network & internet** + **Bluetooth & devices**.
7. **Accounts** + **Time & language** + **Accessibility** + **Gaming**.
8. **Privacy & security** + **System Update**.
9. **Administration** (services/eventvwr/users/kded/session/SDDM/Plymouth) — migrate the
   existing native admin pages into the Win11 shell.
10. **Polish**: HasHDialog everywhere, icon audit (zero blanks), parity sweep, ship via
    hash-suite (new deps: cups…), full smoke.

---

## 9. Risks
- Privilege → `pkexec` argv only. Initramfs/font installs → threaded (kcm_list-hang lesson).
- KConfig key fidelity → diff kdeglobals/kwinrc before/after a real Plasma write to match
  semantics. Don't regress the 9 already-native pages — migrate onto the engine only where
  it's a clean win.
- Scope is large → engine-first is what makes it feasible; settings then are cheap rows.
