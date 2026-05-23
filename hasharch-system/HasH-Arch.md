---
title: HasH-Arch
aliases:
  - HasH-Arch OS
  - HasH Arch
tags:
  - os
  - hash-arch
  - blackarch
  - linux
  - kde
maintainers:
  - NextLVLHasH
  - Opus 4.7
base: BlackArch (Arch Linux)
desktop: KDE Plasma 6 (Wayland)
gpu: NVIDIA RTX 3060 (open driver)
created: 2023
updated: 2026-05-21
---

# HasH-Arch

> [!abstract] What it is
> **HasH-Arch** is a customised Linux distribution — a **fork of [BlackArch](https://blackarch.org/)** (itself an Arch Linux derivative) — built and maintained by **NextLVLHasH** with **Opus 4.7 (1 million context)**. It ships a **fixed, pinned set of repositories** for reproducibility, can be **updated from the original 2023 build with ease** rather than reinstalled, and **rips out the stock Arch/BlackArch GUI in favour of a bespoke [KDE Plasma 6](https://kde.org/plasma-desktop/) desktop**. On top of the security tooling inherited from BlackArch, it is a full daily-driver: AI, development, browsing, notes, gaming and recording — wrapped in a heavily customised, **GPU-accelerated** desktop experience.

---

## 🧬 Lineage

| | |
|---|---|
| **Base distro** | BlackArch → Arch Linux |
| **Desktop** | KDE Plasma 6 (Wayland) — replaces the stock GUI |
| **GPU** | NVIDIA RTX 3060, open kernel driver |
| **First build** | 2023 |
| **Maintained by** | NextLVLHasH + Opus 4.7 (1M context) |
| **Distribution** | ISO remaster (Penguins' eggs), hosted on Google Drive |

> [!info] Fork philosophy
> HasH-Arch is **not a rolling free-for-all**. It pins a **fixed set of repos** so every install resolves to the same known-good package set. This is what makes it possible to take a machine first imaged in **2023** and bring it fully current with a single, predictable update path — no dependency roulette, no reinstall.

> [!important] Desktop overhaul
> The stock Arch/BlackArch GUI was **ripped out and replaced with KDE Plasma 6** (Wayland). KDE/KWin is the foundation for every customisation below — the iOS-style grouping, the dock-aware visualizer, the live wallpaper framework and the in-progress task manager all build on Plasma/KWin rather than the default desktop HasH-Arch shipped with.

---

## 👥 Maintainers

- **NextLVLHasH** — owner, vision, daily driver. Every customisation is shaped around real usage (Edge as the browser, Obsidian for notes, gaming + recording).
- **Opus 4.7 (1,000,000-token context)** — co-maintainer / build engineer for the desktop scripting, KWin/Plasma integration, GPU shaders and ISO remastering.

---

## 📦 Repositories & Updates

> [!tip] Updating from the 2023 build
> Because the repo set is **fixed and curated**, updating an old 2023 image is a low-risk, repeatable operation rather than a gamble. The pinned repos guarantee the same resolution every time, so an aging install can be brought fully current cleanly.

- **Fixed repo set** — curated and pinned for reproducibility.
- **Inherits** the BlackArch repository for security/pentest tooling.
- **Easy in-place upgrade** from the original 2023 build → current.
- ISO image **hosted on Google Drive** (via `rclone`) for distribution.

---

## 🧰 Preinstalled Software

> [!note] Out-of-the-box stack — no first-day setup
> | Category | App |
> |---|---|
> | AI / local models | **LM Studio** |
> | Development | **Visual Studio Code** |
> | Browser | **Microsoft Edge** (default; also hosts lightweight PWAs as background apps) |
> | Cloud | **Google Drive** add-ons (`rclone`; also hosts the ISO) |
> | Notes | **Obsidian** (this vault) |
> | Gaming | **Steam** (Flatpak, fixed desktop integration) |
> | Recording | screen / stream capture tooling |

---

## 🖥️ GPU-Accelerated Visual Engine

> [!success] CPU-light by design
> HasH-Arch runs a **custom GPU-first rendering path for all "visual events"** (the live wallpaper, weather and audio visualizer). The heavy per-pixel and per-frame work is pushed onto the **GPU (RTX 3060)**, leaving the **CPU almost idle**. This is the core architectural decision behind the desktop feeling smooth even with full-screen animated wallpapers on three monitors.

How the load is moved off the CPU:

- **Weather = one procedural GPU fragment shader.** The entire sky, sun, moon, stars, clouds, rain, snow, storm and fog are computed in a single GLSL fragment shader (`weather.frag`), baked to a Qt RHI `.qsb` blob and run via a Qt 6 `ShaderEffect`. It renders **at vsync with near-zero CPU** — the CPU only ticks a clock uniform (`time`) ~24×/sec and updates a handful of uniforms (condition, day/night, wind, aspect, rain colour).
- **Visualizer = GPU scene-graph, not CPU canvas.** The bars are Qt Quick `Rectangle`s drawn directly by the **scene graph on the GPU** — deliberately *not* a CPU-rasterised `Canvas`. The CPU only parses ~64 audio values per frame.
- **Only genuinely-CPU work left:** `cava`'s audio FFT, the tiny QML layout logic, and the weather networking (hourly).
- **Smart throttling:** a KWin guard (`wallpaperguard`) **pauses the wallpaper + visualizer per-screen** whenever a real fullscreen app owns that screen, so the GPU isn't spending cycles rendering hidden pixels.

> [!caution] "GPU driver" clarification
> This is a **GPU-offloaded render pipeline** (fragment shader + scene graph on the NVIDIA open driver), not a bespoke kernel module. The novelty is the *architecture* — driving every desktop visual event through the GPU instead of the CPU — not a custom DRM/KMS driver.

---

## 🌦️ Custom Weather Wallpaper System ✅

> [!success] Done & shipping
> A live, per-screen, GPU-rendered weather wallpaper that mirrors real conditions.

**Pipeline**
1. **Location** — auto from weather-app config or **IP geolocation** fallback (default: Manchester, GB).
2. **Data** — [Open-Meteo](https://open-meteo.com/) `current` endpoint (temperature, WMO weather code, day/night, wind), refreshed **hourly**.
3. **Mapping** — WMO codes → conditions: `clear / clouds / rain / snow / storm / fog`.
4. **Render** — condition + day/night + wind + aspect + rain colour fed as **uniforms** to the GPU shader.

**Features**
- **Per-physical-screen scenes** keyed by monitor geometry (so each screen can show a different condition and they don't shuffle on restart).
- **Primary screen** additionally shows a **temperature + clock + date** overlay (centred under the weather) and the music visualizer.
- iOS-inspired visuals: blue-sky gradient, fancy orbiting sun glow, partly-cloudy (clouds crossing the sun), thin rain streaks with **landing splashes synced to the drops**, round-dot snow, lightning flashes.
- **Configurable rain colour** (hex), wind-driven slant, randomised columns.
- Selectable **code-rain (Matrix)** alternative wallpaper mode.

---

## 🎵 Custom Audio Visualizer ✅

> [!success] Done & shipping
> A dock-aware, GPU-rendered audio visualizer on the primary-screen wallpaper.

**Pipeline**
1. **`cava`** captures the **system audio sink monitor** via PipeWire (`stream.capture.sink=true`) — **never the microphone**.
2. `cava-wallpaper.sh` keeps only the **latest frame** in `$XDG_RUNTIME_DIR/cava-wallpaper.dat` (atomic write).
3. **`MusicWave.qml`** reads it (executable `DataSource`), parses 64 values, applies a **perceptual curve** (`pow(v, 0.6)`) so quiet detail still moves the bars, and renders GPU bars.

**Behaviour**
- **64 bars**, full-screen-width, coloured by level (blue → orange).
- **Dock-aware shape:** a **flat equaliser row sits exactly over the task manager**, and every bar **outside** the dock **drops fully to the bottom of the screen**.
- **Live, symmetric tracking:** the `wallpaperguard` KWin script reports the dock's screen-local centre + width to the wallpaper config; as the task manager **grows, the flat row grows and the side-drops shrink — and the reverse** when it shrinks. Flat bars are counted **symmetrically** from centre (whole bars, not pixel thresholds) so there's **no left/right 1-bar drift**.
- **`cava` smoothing** (`monstercat`, low `noise_reduction`, raised `sensitivity`) for a fluid, responsive wave; **24 fps**.
- Fades out on silence; **pauses with the wallpaper** under the fullscreen guard.

---

## 🎨 Other Desktop Customisations

### 📱 Apple iOS-style App Grouping ✅
Custom plasmoid `com.hash.iosfolders`: draggable home-screen-style folder tiles (Games, Media, Internet, …) that expand into a **single rounded dark popup grid**. **Auto-populates** from the desktop (incl. Flatpak Steam games), right-click → *Remove from desktop*. The popup uses a direct dialog-`backgroundHints` override so only the rounded box shows.

### 🧮 Custom Task Manager & System _(in progress)_
> [!warning] Work in progress
> The dock-aware visualizer and fullscreen guard above are the **first integrated pieces** of a wider custom **Task Manager + system shell**. Still to come: the task manager UI itself and deeper system integration.

### 🚀 Editable Launcher ✅
`com.hash.kickoff`: pin removed, **single power dropdown**, app categories surfaced in Places, custom hacker icon.

### 🔐 Login / Lock ✅
SDDM login made **1:1 with the lock screen**; service accounts hidden from login.

> [!quote] Egg-ready
> Assets live in **system locations** (`/etc`, `/usr/share`, `/etc/skel`) so they carry into every new user on a fresh HasH-Arch install during the **Penguins' eggs** ISO remaster.

---

## 🛠️ Where It Can Be Improved

> [!todo] Honest backlog
> These are known rough edges / opportunities, kept here so they aren't lost.

### Visualizer
- **Polling cost** — `MusicWave` spawns a `cat` process ~24×/sec to read the frame file. A persistent pipe/socket reader or a small native QML plugin would remove the per-frame process spawn.
- **Dock-tracking race** — right after a `plasmashell` restart the panels respawn and the dock is briefly mis-sized; a short retry/poll in the guard would avoid the transient bad width.
- **Bar↔icon alignment** — the flat row matches dock *width* to within ½ a bar; snapping bar boundaries to actual dock-icon centres would make it pixel-perfect.
- **Feature polish** — peak-hold caps, gravity/decay, per-band colour gradients.

### Weather
- **Shader build** — `weather.frag` is hand-baked with `qsb`; a build step/Makefile would make edits less manual.
- **Qt file:// bug workaround** — file reads currently go through an executable `DataSource` (`cat`) because `file://` XHR is broken in this Qt build; worth revisiting on Qt upgrades.
- **More fidelity** — smooth day↔night transitions, moon phases, fog depth, hourly forecast strip.

### GPU pipeline
- **Audio on GPU** — `cava`'s FFT is still CPU; a compute-shader audio path would push even that to the GPU.
- **Frame pacing** — unify the 24 fps caps and expose them as one setting.

### System / packaging
- **Guard reloads** — the KWin guard is hot-reloaded during dev; ensure the packaged version auto-loads cleanly on every boot.
- **Update tooling** — a single `hash-arch-update` wrapper around the pinned repos would make the 2023→current path one command.
- **Versioning** — tag ISO releases so installs can report their build.

---

## 🗺️ Roadmap & Status

- [x] BlackArch fork with fixed/pinned repos
- [x] Stock GUI ripped out → **KDE Plasma 6**
- [x] Easy in-place update from the 2023 build
- [x] Preinstalled: LM Studio, VS Code, Edge, Google Drive, Obsidian, Steam, recording
- [x] **GPU-offloaded visual engine** (shader + scene graph)
- [x] **Custom weather wallpaper system**
- [x] **Custom audio visualizer** (dock-aware, live-tracking)
- [x] Fullscreen guard (per-screen pause + dock geometry)
- [x] iOS-style app grouping (`com.hash.iosfolders`)
- [x] Editable Kickoff launcher (`com.hash.kickoff`)
- [x] SDDM/lock-screen parity
- [ ] Custom **Task Manager** UI (in progress)
- [ ] Custom **system shell** (in progress)
- [ ] One-command update wrapper
- [ ] Published ISO remaster on Google Drive

---

## 🔗 Related notes

- [[Customisations]]
- [[Update Guide]]
- [[ISO Remaster (eggs)]]
- [[Desktop Components]]
- [[GPU Visual Engine]]

> [!note]- Credits
> Maintained by **NextLVLHasH** & **Opus 4.7 (1M context)**. Based on BlackArch / Arch Linux. Desktop: KDE Plasma 6 on an NVIDIA RTX 3060.
