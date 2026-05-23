#!/usr/bin/env python3
"""Scan the desktop (and the flatpak Steam sandbox Desktop) for *.desktop files,
categorise them iOS-folder style, and write a manifest the com.hash.iosfolders
applet renders. Also FIXES flatpak Steam game shortcuts: their Exec is
`steam steam://rungameid/<id>` which fails outside the sandbox, so we rewrite it
to `flatpak run com.valvesoftware.Steam steam://rungameid/<id>` and emit a proper
launchable .desktop into ~/.local/share/applications (so it works everywhere)."""
import glob, json, os, re, shutil

HOME = os.path.expanduser("~")
STEAM_SANDBOX = os.path.join(HOME, ".var/app/com.valvesoftware.Steam")
ICON_THEME = os.path.join(HOME, ".local/share/icons/hicolor")   # where we install game icons
# Where "Add to desktop" lands: real ~/Desktop AND the flatpak sandbox Desktop.
# Steam's own persistent per-game shortcuts (.local/share/applications) are
# included so games stay in the iOS folder even after their ~/Desktop icon is
# trashed — they're sourced from Steam's library, not the desktop copy.
SCAN_DIRS = [os.path.join(HOME, "Desktop"),
             os.path.join(STEAM_SANDBOX, "Desktop"),
             os.path.join(STEAM_SANDBOX, ".local/share/applications")]
APPS_OUT = os.path.join(HOME, ".local/share/applications")   # fixed shortcuts go here
OUT_DIR = os.path.join(HOME, ".local/share/com.hash.iosfolders")
OUT = os.path.join(OUT_DIR, "folders.json")

CAT_MAP = [
    ("Game",        ("Games",       "steam")),
    ("AudioVideo",  ("Media",       "applications-multimedia")),
    ("Audio",       ("Media",       "applications-multimedia")),
    ("Video",       ("Media",       "applications-multimedia")),
    ("Player",      ("Media",       "applications-multimedia")),
    ("Development", ("Development",  "applications-development")),
    ("IDE",         ("Development",  "applications-development")),
    ("Graphics",    ("Graphics",    "applications-graphics")),
    ("Office",      ("Office",       "applications-office")),
    ("WebBrowser",  ("Internet",    "applications-internet")),
    ("Network",     ("Internet",    "applications-internet")),
    ("Email",       ("Internet",    "applications-internet")),
    ("System",      ("Utilities",   "applications-utilities")),
    ("Settings",    ("Utilities",   "applications-utilities")),
    ("Utility",     ("Utilities",   "applications-utilities")),
]
OTHER = ("Other", "applications-other")
FIELD_CODES = re.compile(r"%[uUfFickdDnNvm]")
NAME_HINTS = [(("music", "spotify", "netflix", "youtube", "video", "tidal", "podcast"),
               ("Media", "applications-multimedia"))]
RUNGAME_RE = re.compile(r"rungameid/(\d+)")
STEAMICON_RE = re.compile(r"steam_icon_(\d+)")


def parse_desktop(path):
    fields = {}
    try:
        with open(path, encoding="utf-8", errors="ignore") as fh:
            in_entry = False
            for line in fh:
                line = line.rstrip("\n")
                if line.startswith("["):
                    in_entry = line.strip() == "[Desktop Entry]"
                    continue
                if in_entry and "=" in line:
                    k, v = line.split("=", 1)
                    fields.setdefault(k.strip(), v.strip())
    except OSError:
        return None
    return fields


def steam_icon_path(gid):
    base = os.path.join(STEAM_SANDBOX, ".local/share/icons/hicolor")
    for size in ("256x256", "128x128", "96x96", "64x64", "48x48"):
        p = os.path.join(base, size, "apps", "steam_icon_%s.png" % gid)
        if os.path.exists(p):
            return p
    return None


def install_steam_icon(gid):
    """Copy the game's icon out of the Steam sandbox into the user icon theme so
    it resolves by NAME (steam_icon_<gid>) everywhere — launcher grid, desktop,
    iOS folders. Absolute-path Icon= entries don't render reliably in Kicker."""
    base = os.path.join(STEAM_SANDBOX, ".local/share/icons/hicolor")
    name = "steam_icon_%s" % gid
    installed = False
    for size in ("256x256", "128x128", "96x96", "64x64", "48x48", "32x32", "24x24", "16x16"):
        src = os.path.join(base, size, "apps", name + ".png")
        if os.path.exists(src):
            dst_dir = os.path.join(ICON_THEME, size, "apps")
            os.makedirs(dst_dir, exist_ok=True)
            try:
                shutil.copyfile(src, os.path.join(dst_dir, name + ".png"))
                installed = True
            except OSError:
                pass
    return name if installed else None


def fix_flatpak_steam(fields):
    """If this is a flatpak Steam game shortcut, write a corrected launchable
    .desktop and return its (name, icon, exec, file). Else return None."""
    exec_ = fields.get("Exec", "")
    icon_ = fields.get("Icon", "")
    m = RUNGAME_RE.search(exec_) or STEAMICON_RE.search(icon_)
    if not m:
        return None
    gid = m.group(1)
    name = fields.get("Name", "Steam Game " + gid)
    # install the icon into the user theme and reference it BY NAME (reliable in
    # Kicker, the desktop, and Kirigami.Icon); fall back to the Steam logo.
    icon_name = install_steam_icon(gid)
    desktop_icon = icon_name if icon_name else "com.valvesoftware.Steam"
    manifest_icon = icon_name if icon_name else "com.valvesoftware.Steam"
    new_exec = "flatpak run com.valvesoftware.Steam steam://rungameid/%s" % gid
    os.makedirs(APPS_OUT, exist_ok=True)
    out = os.path.join(APPS_OUT, "steam-flatpak-%s.desktop" % gid)
    with open(out, "w", encoding="utf-8") as fh:
        # NOTE: deliberately NO StartupWMClass. A rungameid shortcut spawns no
        # window of its own — it asks the Steam client (window class "steam") to
        # launch. Claiming StartupWMClass=steam here makes KDE bind the Steam
        # client window to this game shortcut, so the Steam launcher/taskbar shows
        # the game's art instead of the Steam logo. Omitting it leaves the Steam
        # window matched to com.valvesoftware.Steam.desktop (the real Steam icon).
        fh.write("[Desktop Entry]\n"
                 "Type=Application\n"
                 "Name=%s\n"
                 "Exec=%s\n"
                 "Icon=%s\n"
                 "Categories=Game;X-HasH-Games;\n"   # curated Games group in the launcher
                 "Terminal=false\n" % (name, new_exec, desktop_icon))
    os.chmod(out, 0o755)
    return {"name": name, "icon": manifest_icon, "exec": new_exec, "file": out}


def classify(fields, name):
    cats = fields.get("Categories", "")
    for token, group in CAT_MAP:
        if re.search(r"(^|;)" + re.escape(token) + r"(;|$)", cats):
            return group
    low = name.lower()
    for keys, group in NAME_HINTS:
        if any(k in low for k in keys):
            return group
    return OTHER


def main():
    groups = {}
    seen = set()
    for d in SCAN_DIRS:
        for path in sorted(glob.glob(os.path.join(d, "*.desktop"))):
            real = os.path.realpath(path)
            f = parse_desktop(real) or {}
            if f.get("NoDisplay", "").lower() == "true":
                continue

            fixed = fix_flatpak_steam(f)
            if fixed:
                item = fixed
                gname, gicon = ("Games", "steam")
            else:
                name = f.get("Name", os.path.basename(path).rsplit(".", 1)[0])
                item = {"name": name,
                        "icon": f.get("Icon", "application-x-executable"),
                        "exec": FIELD_CODES.sub("", f.get("Exec", "")).strip(),
                        "file": real}
                gname, gicon = classify(f, name)

            # the on-desktop entry to delete on "remove" (the symlink/file in the
            # scanned dir — NOT its realpath target, which may be a system file)
            item["source"] = path

            key = item["name"] + "|" + gname
            if key in seen:
                continue
            seen.add(key)
            groups.setdefault(gname, {"name": gname, "icon": gicon, "items": []})
            groups[gname]["items"].append(item)

    order = ["Games", "Media", "Internet", "Development", "Graphics",
             "Office", "Utilities", "Other"]
    ordered = [groups[g] for g in order if g in groups]
    ordered += [v for k, v in groups.items() if k not in order]

    os.makedirs(OUT_DIR, exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump({"groups": ordered}, fh, indent=2)
    print("wrote %s (%d groups)" % (OUT, len(ordered)))


if __name__ == "__main__":
    main()
