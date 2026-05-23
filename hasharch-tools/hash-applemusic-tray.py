#!/usr/bin/env python3
"""Apple Music background tray icon for HasH-Arch (Edge / Chrome / Brave).

The Apple Music PWA runs as a background app (no taskbar entry). This puts an
Apple Music icon in the system tray so it can be reopened/raised with a click.
Browser + app id are read from ~/.config/hash/applemusic.conf (written by
hash-applemusic-setup), so the SAME script serves any Chromium browser.
"""
import os
import subprocess
import sys
import time

from PyQt6.QtWidgets import QApplication, QSystemTrayIcon, QMenu
from PyQt6.QtGui import QIcon

# ---- config (browser-specific bits) written by hash-applemusic-setup ----
CONF = os.path.expanduser("~/.config/hash/applemusic.conf")
cfg = {"BROWSER_BIN": "/opt/microsoft/msedge/microsoft-edge",
       "APP_ID": "blgdilankhbcpipclgpdndahbehalgkh",
       "DESKTOP_PREFIX": "msedge",
       "ICON": "lxmusic",
       "URL": "https://music.apple.com/"}
try:
    for ln in open(CONF):
        ln = ln.strip()
        if "=" in ln and not ln.startswith("#"):
            k, v = ln.split("=", 1)
            cfg[k.strip()] = v.strip()
except Exception:
    pass

APP_ID = cfg["APP_ID"]
LAUNCH = [cfg["BROWSER_BIN"],
          "--enable-features=VaapiVideoDecoder,VaapiVideoEncoder",
          "--ignore-gpu-blocklist", "--enable-gpu-rasterization", "--enable-zero-copy",
          "--profile-directory=Default",
          "--app-id=" + APP_ID,
          "--app-url=" + cfg["URL"]]

_KWIN = '''
var ws = workspace.windowList ? workspace.windowList() : workspace.clientList();
var found = 0;
for (var i = 0; i < ws.length; i++) {
    var w = ws[i];
    if (("" + w.resourceClass).indexOf("%s") >= 0) {
        w.minimized = false;
        if (w.desktops !== undefined) w.desktops = [workspace.currentDesktop];
        workspace.activeWindow = w; found++; break;
    }
}
print("AMTRAY_FOUND=" + found);
''' % APP_ID
_KWIN_CLOSE = '''
var ws = workspace.windowList ? workspace.windowList() : workspace.clientList();
for (var i = 0; i < ws.length; i++) {
    var w = ws[i];
    if (("" + w.resourceClass).indexOf("%s") >= 0) w.closeWindow();
}
print("AMTRAY_CLOSED");
''' % APP_ID


def _qdbus(*a):
    return subprocess.run(["qdbus6", "org.kde.KWin", *a], capture_output=True, text=True)


def _run_kwin(script, name):
    path = "/tmp/hash-amtray-%s.kwin.js" % name
    open(path, "w").write(script)
    _qdbus("/Scripting", "org.kde.kwin.Scripting.unloadScript", name)
    since = subprocess.run(["date", "+%s"], capture_output=True, text=True).stdout.strip()
    _qdbus("/Scripting", "org.kde.kwin.Scripting.loadScript", path, name)
    _qdbus("/Scripting", "org.kde.kwin.Scripting.start")
    time.sleep(0.4)
    log = subprocess.run(["journalctl", "_COMM=kwin_wayland", "--since", "@" + since, "-o", "cat"],
                         capture_output=True, text=True).stdout
    _qdbus("/Scripting", "org.kde.kwin.Scripting.unloadScript", name)
    return log


def open_app():
    log = _run_kwin(_KWIN, "amtray")
    found = any(l.strip().endswith("=1") for l in log.splitlines() if "AMTRAY_FOUND=" in l)
    if not found:
        subprocess.Popen(LAUNCH, start_new_session=True)


def close_app():
    _run_kwin(_KWIN_CLOSE, "amtrayclose")


def main():
    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)
    icon = QIcon.fromTheme(cfg["ICON"])                 # themed (lxmusic — fits the build)
    if icon.isNull():
        icon = QIcon.fromTheme("apple-music")
    if icon.isNull():
        icon = QIcon.fromTheme("multimedia-player")
    tray = QSystemTrayIcon(icon)
    tray.setToolTip("Apple Music")
    menu = QMenu()
    menu.addAction("Open Apple Music", open_app)
    menu.addSeparator()

    def quit_all():
        close_app(); tray.hide(); app.quit()
    menu.addAction("Quit", quit_all)
    tray.setContextMenu(menu)
    tray.activated.connect(lambda r: open_app() if r in (
        QSystemTrayIcon.ActivationReason.Trigger,
        QSystemTrayIcon.ActivationReason.DoubleClick) else None)
    tray.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
