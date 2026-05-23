#!/usr/bin/env bash
# Make OBS minimize to the system tray (background) like Apple Music, via OBS's
# native tray feature. OBS only reads global.ini at startup but rewrites it on
# exit (dropping keys it didn't load), so this re-asserts the keys whenever the
# file changes. Idempotent + atomic, so it converges to keys-present after OBS's
# exit-write without corrupting a concurrent write. (Effect needs an OBS restart.)
set -uo pipefail
ini="$HOME/.config/obs-studio/global.ini"
[ -f "$ini" ] || exit 0

python3 - "$ini" <<'PY'
import os, re, sys, tempfile
p = sys.argv[1]
txt = open(p, encoding="utf-8").read()
want = {"SysTrayEnabled": "true", "SysTrayWhenStarted": "false", "SysTrayMinimizeToTray": "true"}
m = re.search(r'(?ms)^\[BasicWindow\]\s*\n(.*?)(?=^\[|\Z)', txt)
changed = False
if not m:
    sec = "".join("%s=%s\n" % (k, v) for k, v in want.items())
    if not txt.endswith("\n"):
        txt += "\n"
    txt += "\n[BasicWindow]\n" + sec
    changed = True
else:
    body = m.group(1)
    for k, v in want.items():
        if re.search(r'(?m)^%s=' % re.escape(k), body):
            nb = re.sub(r'(?m)^%s=.*$' % re.escape(k), "%s=%s" % (k, v), body)
        else:
            nb = body + ("%s=%s\n" % (k, v))
        if nb != body:
            body, changed = nb, True
    if changed:
        txt = txt[:m.start(1)] + body + txt[m.end(1):]
if changed:
    d = os.path.dirname(p)
    fd, tmp = tempfile.mkstemp(dir=d)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(txt)
    os.replace(tmp, p)        # atomic
    print("OBS tray config applied")
else:
    print("OBS tray config already set")
PY
