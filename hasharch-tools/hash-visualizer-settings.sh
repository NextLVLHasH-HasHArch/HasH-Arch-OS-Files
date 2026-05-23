#!/usr/bin/env bash
# Music visualizer settings dialog for the HasH Settings tab. Enable/disable and
# pick a colour scheme; writes to the com.hash.matrixrain wallpaper config (live).
set -uo pipefail

sel=$(kdialog --title "Music Visualizer" --menu "Choose the visualizer mode:" \
  level   "Enabled — reactive (blue → orange)" \
  cyan    "Enabled — cyan / blue" \
  rainbow "Enabled — rainbow" \
  warm    "Enabled — warm (orange / red)" \
  off     "Disabled" 2>/dev/null) || exit 0
[ -z "$sel" ] && exit 0

if [ "$sel" = "off" ]; then show="off"; color="level"; else show="on"; color="$sel"; fi

qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
var ds = desktops();
for (var i = 0; i < ds.length; i++) {
    var d = ds[i]; var g = screenGeometry(d.screen);
    d.currentConfigGroup = ['Wallpaper', 'com.hash.matrixrain', 'General'];
    d.writeConfig('visualizerColor', '$color');
    var primary = (d.readConfig('showInfo') === 'true') || g.x === 2560;
    d.writeConfig('showVisualizer', ('$show' === 'on') ? primary : false);
}
" >/dev/null 2>&1

kdialog --passivepopup "Visualizer: $sel" 4 2>/dev/null
