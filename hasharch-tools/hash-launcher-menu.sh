#!/usr/bin/env bash
# Build the HasH-Arch custom launcher menu (Kickoff):
#   * Applications tab  -> 6 curated categories (Office/Games/Dev/Internet/Media/Creation)
#   * Places tab        -> BlackArch tools grouped by FUNCTION (Scanner, Webapp, ...)
# Implemented as a full user override of plasma-applications.menu (additive merged
# menu removed to avoid duplicate same-named categories). Fully reversible:
#   rm ~/.config/menus/plasma-applications.menu
#   rm ~/.local/share/desktop-directories/{hash-*,blackarch-*}.directory
#   rm ~/.config/menus/applications-merged/hash-categories.menu ; kbuildsycoca6
set -uo pipefail

DIRS="$HOME/.local/share/desktop-directories"
MENUDIR="$HOME/.config/menus"
mkdir -p "$DIRS" "$MENUDIR"

# the old additive menu caused Development/Games/Office duplicates -> drop it
rm -f "$MENUDIR/applications-merged/hash-categories.menu"

mkdir_dir() { # <file> <Name> <Icon>
  printf '[Desktop Entry]\nType=Directory\nName=%s\nIcon=%s\n' "$2" "$3" > "$DIRS/$1"
}

# ---- curated Applications categories (.directory files from groups.json) ----
GROUPS_JSON="$HOME/.local/share/com.hash.kickoff/groups.json"
python3 - "$GROUPS_JSON" "$DIRS" <<'PY'
import json, os, sys
gj, dirs = sys.argv[1], sys.argv[2]
groups = json.load(open(gj)).get("groups", []) if os.path.exists(gj) else []
for g in groups:
    with open(os.path.join(dirs, "hash-%s.directory" % g["slug"]), "w") as f:
        f.write("[Desktop Entry]\nType=Directory\nName=%s\nIcon=%s\n"
                % (g["name"], g.get("icon", "applications-other")))
PY

# ---- BlackArch functional categories: friendly name | X-BlackArch subcategory | icon ----
BA=(
  "Web Application|Webapp|applications-internet"
  "Scanners|Scanner|preferences-system-network"
  "Recon|Recon|edit-find"
  "Networking|Networking|network-workgroup"
  "Sniffers|Sniffer|network-wired"
  "Spoofing|Spoof|view-conversation-balloon"
  "Proxies|Proxy|preferences-system-network-proxy"
  "Fuzzers|Fuzzer|tools-wizard"
  "Exploitation|Exploitation|security-low"
  "Crackers|Cracker|dialog-password"
  "Crypto|Crypto|document-encrypt"
  "Wireless|Wireless|network-wireless"
  "Forensics|Forensic|edit-find-project"
  "Anti-Forensic|Anti-Forensic|edit-clear-history"
  "Automation|Automation|system-run"
  "Defensive|Defensive|security-high"
  "Backdoors|Backdoor|view-hidden"
  "Tunnels|Tunnel|network-vpn"
  "Fingerprinting|Fingerprint|fingerprint"
  "Reversing|Reversing|debug-step-into"
  "Disassemblers|Disassembler|application-x-executable"
  "Debuggers|Debugger|tools-report-bug"
  "Windows|Windows|distributor-logo-windows"
  "Bluetooth|Bluetooth|network-bluetooth"
  "VoIP|Voip|call-start"
  "Social|Social|system-users"
  "Honeypots|Honeypot|server-database"
  "Misc|Misc|applications-other"
)
for e in "${BA[@]}"; do
  IFS='|' read -r name sub icon <<<"$e"
  mkdir_dir "blackarch-$(echo "$sub" | tr 'A-Z' 'a-z').directory" "$name" "$icon"
done

# ---- the menu ----
menu="$MENUDIR/plasma-applications.menu"
{
cat <<'HEAD'
<!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
  "http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd">
<Menu>
	<Name>Applications</Name>
	<Directory>kde-main.directory</Directory>
	<DefaultAppDirs/>
	<DefaultDirectoryDirs/>
	<DefaultLayout>
		<Merge type="menus"/>
		<Merge type="files"/>
	</DefaultLayout>

	<!-- catch-all so non-curated apps are still reachable (All Applications) -->
	<Menu>
		<Name>Applications</Name>
		<Directory>kf5-unknown.directory</Directory>
		<OnlyUnallocated/>
		<Include><All/></Include>
	</Menu>

	<!-- ===== curated Applications categories ===== -->
HEAD

# Curated categories from groups.json. Membership is EXPLICIT only: an app shows
# here solely if it carries this group's X-HasH-<Slug> tag (set by the user via
# right-click, by hash-app-categories, or auto-applied to flatpaks by
# hash-cat sync-flatpaks). This deliberately does NOT auto-include every system
# app with a matching freedesktop category, so pentesting/system tools never leak in.
python3 - "$HOME/.local/share/com.hash.kickoff/groups.json" <<'PY'
import json, os, sys
gj = sys.argv[1]
groups = json.load(open(gj)).get("groups", []) if os.path.exists(gj) else []
for g in groups:
    slug = g["slug"]; tag = "X-HasH-" + slug.capitalize()
    inc = "<Category>%s</Category>" % tag
    print("\t<Menu>\n\t\t<Name>HasH-%s</Name>\n\t\t<Directory>hash-%s.directory</Directory>\n\t\t<Include>%s</Include>\n\t</Menu>" % (slug, slug, inc))
PY

echo '	<!-- ===== BlackArch tools by function ===== -->'
for e in "${BA[@]}"; do
  IFS='|' read -r name sub icon <<<"$e"
  low=$(echo "$sub" | tr 'A-Z' 'a-z')
  printf '\t<Menu>\n\t\t<Name>BA-%s</Name>\n\t\t<Directory>blackarch-%s.directory</Directory>\n\t\t<Include><Category>X-BlackArch-%s</Category></Include>\n\t</Menu>\n' "$sub" "$low" "$sub"
done

cat <<'FOOT'
	<DefaultMergeDirs/>
</Menu>
FOOT
} > "$menu"

echo "wrote $menu"
echo "rebuilding sycoca..."
kbuildsycoca6 2>&1 | grep -iE "error|parse" | head
echo "done."
