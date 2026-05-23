#!/usr/bin/env bash
# HasH-Arch BlackArch handling:
#   1. Hide every BlackArch tool from KRunner / "All Applications" / menus by
#      shadowing it with a user .desktop override that sets NoDisplay=true.
#   2. Emit blackarch.json grouping the tools BY FUNCTION (Scanners, Web
#      Application, Recon, ...) read straight from the system .desktop files
#      (ignoring NoDisplay) so the custom Kickoff Places tab can still list them.
# Reversible: rm the overrides + the json, run update-desktop-database.
set -uo pipefail

SYS=/usr/share/applications
USR="$HOME/.local/share/applications"
OUT_DIR="$HOME/.local/share/com.hash.kickoff"
OUT="$OUT_DIR/blackarch.json"
mkdir -p "$USR" "$OUT_DIR"

python3 - "$SYS" "$USR" "$OUT" <<'PY'
import os, sys, glob, json, re, shutil, subprocess

# tools whose .desktop name doesn't match any binary -> the real command
ALIAS = {"metasploit": "msfconsole", "armitage": "armitage", "beef": "beef"}

def _pkg_bins(pkg):
    """/usr/bin executables shipped by an installed package (empty if none)."""
    r = subprocess.run(["pacman", "-Qlq", pkg], capture_output=True, text=True)
    if r.returncode != 0:
        return None        # not an installed package
    return [f for f in r.stdout.splitlines()
            if f.startswith("/usr/bin/") and os.path.isfile(f) and os.access(f, os.X_OK)]


def resolve_bin(desktop_path, name, current):
    """Resolve a tool's real runnable binary. Returns the path, or "" if the
    package ships NO executable (data/library packages like seclists/exploitdb)."""
    if current and current.startswith("/") and os.path.exists(current):
        return current
    cand = ALIAS.get(name, name)
    for p in ("/usr/bin/" + cand, "/usr/sbin/" + cand):
        if os.path.exists(p):
            return p
    w = shutil.which(cand)
    if w:
        return w
    # the BlackArch package name usually IS the tool name -> inspect its files
    nm_compact = re.sub(r"[^a-z0-9]", "", name.lower())
    for pkg in (cand, name):
        bins = _pkg_bins(pkg)
        if bins is None:
            continue                                  # package not installed under this name
        for b in bins:                                # exact basename
            if os.path.basename(b) == name:
                return b
        for b in bins:                                # name (compacted) is a substring
            if nm_compact and nm_compact in re.sub(r"[^a-z0-9]", "", os.path.basename(b).lower()):
                return b
        if bins:
            return bins[0]                            # first executable the package ships
        return ""                                     # installed but ships NO binary (data pkg)
    return current

SYS, USR, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
FIELD = re.compile(r"%[uUfFickdDnNvm]")
SUBCAT = re.compile(r"X-BlackArch-([A-Za-z]+)")

# friendly names for the functional subcategories
NICE = {
    "Webapp":"Web Application","Scanner":"Scanners","Recon":"Recon",
    "Networking":"Networking","Sniffer":"Sniffers","Spoof":"Spoofing",
    "Proxy":"Proxies","Fuzzer":"Fuzzers","Exploitation":"Exploitation",
    "Cracker":"Crackers","Crypto":"Crypto","Wireless":"Wireless",
    "Forensic":"Forensics","Automation":"Automation","Defensive":"Defensive",
    "Backdoor":"Backdoors","Tunnel":"Tunnels","Fingerprint":"Fingerprinting",
    "Reversing":"Reversing","Disassembler":"Disassemblers","Debugger":"Debuggers",
    "Windows":"Windows","Bluetooth":"Bluetooth","Voip":"VoIP","Social":"Social",
    "Honeypot":"Honeypots","Misc":"Misc","Anti":"Anti-Forensic",
}
# preferred order (most useful first)
ORDER = ["Web Application","Scanners","Recon","Networking","Exploitation",
         "Fuzzers","Crackers","Sniffers","Spoofing","Crypto","Wireless",
         "Forensics","Proxies","Automation","Defensive","Misc"]

# per-category (fancy) sidebar icons
GICON = {
    "Web Application":"applications-internet","Scanners":"preferences-system-network",
    "Recon":"edit-find","Networking":"network-workgroup","Sniffers":"network-wired",
    "Spoofing":"view-conversation-balloon","Proxies":"preferences-system-network-proxy",
    "Fuzzers":"tools-wizard","Exploitation":"security-low","Crackers":"dialog-password",
    "Crypto":"document-encrypt","Wireless":"network-wireless","Forensics":"edit-find-project",
    "Anti-Forensic":"edit-clear-history","Automation":"system-run","Defensive":"security-high",
    "Backdoors":"view-hidden","Tunnels":"network-vpn","Fingerprinting":"fingerprint",
    "Reversing":"debug-step-into","Disassemblers":"application-x-executable",
    "Debuggers":"tools-report-bug","Windows":"distributor-logo-windows",
    "Bluetooth":"network-bluetooth","VoIP":"call-start","Social":"system-users",
    "Honeypots":"server-database","Misc":"applications-other",
}

def parse(path):
    f = {}
    try:
        with open(path, encoding="utf-8", errors="ignore") as fh:
            ine = False
            for ln in fh:
                ln = ln.rstrip("\n")
                if ln.startswith("["):
                    ine = ln.strip() == "[Desktop Entry]"; continue
                if ine and "=" in ln:
                    k, v = ln.split("=", 1); f.setdefault(k.strip(), v.strip())
    except OSError:
        return None
    return f

# apps the user promoted into the Applications page stay visible / out of Places
PROMOTED = os.path.join(os.path.expanduser("~"), ".local/share/com.hash.kickoff/promoted.txt")
promoted = set()
if os.path.exists(PROMOTED):
    promoted = set(l.strip() for l in open(PROMOTED) if l.strip())

groups = {}
hidden = 0
for path in sorted(glob.glob(os.path.join(SYS, "*.desktop"))):
    f = parse(path) or {}
    cats = f.get("Categories", "")
    if "X-BlackArch" not in cats:
        continue
    base = os.path.basename(path)
    if base in promoted:
        continue        # promoted to Applications -> don't hide, don't list in Places
    # 1) hide it from KRunner/all-apps via a NoDisplay override
    with open(path, encoding="utf-8", errors="ignore") as fh:
        body = fh.read()
    if re.search(r"^NoDisplay=", body, re.M):
        body = re.sub(r"^NoDisplay=.*$", "NoDisplay=true", body, count=1, flags=re.M)
    else:
        body = body.replace("[Desktop Entry]", "[Desktop Entry]\nNoDisplay=true", 1)
    with open(os.path.join(USR, base), "w", encoding="utf-8") as fh:
        fh.write(body)
    hidden += 1
    # 2) classify by its first known functional subcategory
    subs = SUBCAT.findall(cats)
    nice = None
    for s in subs:
        if s in NICE and NICE[s] != "Misc":
            nice = NICE[s]; break
    if not nice:
        nice = next((NICE[s] for s in subs if s in NICE), "Misc")
    raw_exec = f.get("Exec", "")
    exec_ = FIELD.sub("", raw_exec).strip()
    nm = f.get("Name", base.rsplit(".", 1)[0])
    # BlackArch shortcuts are `sh -c '/usr/bin/TOOL;$SHELL'` -> pull out the binary
    mexe = re.search(r"sh -c ['\"](.+?);\s*\$SHELL['\"]", raw_exec)
    raw_bin = (mexe.group(1).strip() if mexe else exec_)
    binary = resolve_bin(path, nm, raw_bin)
    if raw_bin != binary or (raw_bin.startswith("/") and not os.path.exists(raw_bin)):
        if binary == "":
            st = "DATA/LIB (no command)"
        elif os.path.exists(binary):
            st = "OK -> " + binary
        else:
            st = "STILL MISSING -> " + binary
        sys.stderr.write("  %-24s %-22s  %s\n" % (nm, raw_bin, st))
    item = {
        "name": nm,
        "icon": f.get("Icon", "application-x-executable"),
        "exec": exec_,
        "bin": binary,                                          # the tool itself (resolved)
        "terminal": f.get("Terminal", "").lower() == "true",     # console app?
        "comment": f.get("Comment", ""),
        "file": path,
    }
    groups.setdefault(nice, []).append(item)

def grp(name, items):
    return {"name": name, "icon": GICON.get(name, "applications-other"),
            "items": sorted(items, key=lambda x: x["name"].lower())}

ordered = []
for name in ORDER:
    if name in groups:
        ordered.append(grp(name, groups.pop(name)))
for name in sorted(groups):
    ordered.append(grp(name, groups[name]))

with open(OUT, "w", encoding="utf-8") as fh:
    json.dump({"groups": ordered}, fh, indent=2)
print("hid %d BlackArch tools; %d functional groups -> %s" % (hidden, len(ordered), OUT))
PY

update-desktop-database "$USR" 2>/dev/null
echo "done."
