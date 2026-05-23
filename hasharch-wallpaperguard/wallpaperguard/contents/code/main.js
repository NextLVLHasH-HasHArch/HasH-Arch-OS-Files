/*
 * Wallpaper Fullscreen/Maximize Guard + Dock Tracker (KWin script).
 *
 *  - Pauses the com.hash.matrixrain wallpaper ONLY on the screen that currently
 *    has a real fullscreen OR a fully-maximized application (freezes wallpaper +
 *    visualizer there). Every other screen keeps animating.
 *  - Reports the bottom dock (task manager) geometry, screen-local, to each
 *    wallpaper so the audio visualizer's flat row tracks the dock width live as
 *    it grows/shrinks. dockCenter = -1 when there's no bottom dock on a screen.
 */

var lastKey = null;

// KWin MaximizeMode: Restore=0, Vertical=1, Horizontal=2, Full=3 (V|H).
var MAXIMIZE_FULL = 3;

function windows() {
    return (typeof workspace.windowList === "function")
        ? workspace.windowList()
        : workspace.clientList();
}

// True when a normal window is maximized in BOTH directions. Different KWin
// versions expose this as the maximizeMode enum or as a maximized boolean.
function isMaximizedFull(w) {
    if (typeof w.maximizeMode !== "undefined")
        return w.maximizeMode === MAXIMIZE_FULL;
    if (typeof w.maximized !== "undefined")
        return w.maximized === true;
    return false;
}

// Screen-covering windows reported as frame CENTRES [cx, cy] (rounded). We use
// the centre (not the origin) so the plasmashell side can map each window onto
// the screen it lives on regardless of panel struts: a maximized window's frame
// origin is shifted by top/left panels, but its centre still falls inside the
// screen. Both real fullscreen apps and fully-maximized windows qualify.
function coveringCentres(except) {
    var list = windows();
    var centres = [];
    for (var i = 0; i < list.length; i++) {
        var w = list[i];
        if (w === except) continue;   // a window being removed lingers in the list
        if (!w || !w.normalWindow || w.minimized || !w.frameGeometry) continue;
        if (w.fullScreen || isMaximizedFull(w)) {
            var g = w.frameGeometry;
            centres.push([Math.round(g.x + g.width / 2), Math.round(g.y + g.height / 2)]);
        }
    }
    return centres;
}

// All bottom dock panels as [x, y, width, height] (global px).
function bottomDocks(except) {
    var list = windows();
    var rects = [];
    for (var i = 0; i < list.length; i++) {
        var w = list[i];
        if (w === except || !w || w.dock !== true || w.minimized || !w.frameGeometry)
            continue;
        var g = w.frameGeometry;
        rects.push([Math.round(g.x), Math.round(g.y), Math.round(g.width), Math.round(g.height)]);
    }
    return rects;
}

function apply(except) {
    var fs = coveringCentres(except);
    var docks = bottomDocks(except);
    var key = JSON.stringify(fs) + "|" + JSON.stringify(docks);
    if (key === lastKey)
        return;
    lastKey = key;
    callDBus("org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell",
        "evaluateScript",
        'var covered = ' + JSON.stringify(fs) + ';' +
        'var docks = ' + JSON.stringify(docks) + ';' +
        'for (const d of desktops()) {' +
        '  var g = screenGeometry(d.screen);' +
        '  var p = false;' +
        '  for (var i = 0; i < covered.length; i++) {' +              // pause if a covering window\'s centre is on this screen
        '    if (covered[i][0] >= g.x && covered[i][0] < g.x + g.width &&' +
        '        covered[i][1] >= g.y && covered[i][1] < g.y + g.height) { p = true; break; }' +
        '  }' +
        '  var dc = -1, dw = 0;' +
        '  for (var j = 0; j < docks.length; j++) {' +
        '    var dx = docks[j][0], dy = docks[j][1], dwid = docks[j][2], dh = docks[j][3];' +
        '    var cx = dx + dwid / 2;' +                                  // dock centre (global)
        '    var nearBottom = (dy + dh) >= (g.y + g.height - 120);' +    // it is a BOTTOM dock on this screen
        '    var onScreen = (cx >= g.x && cx <= g.x + g.width);' +
        '    if (nearBottom && onScreen) { dc = cx - g.x; dw = dwid; break; }' +
        '  }' +
        '  d.currentConfigGroup = ["Wallpaper", "com.hash.matrixrain", "General"];' +
        '  d.writeConfig("paused", p);' +
        '  d.writeConfig("dockCenter", dc);' +
        '  d.writeConfig("dockWidth", dw);' +
        '}');
}

function hook(w) {
    if (!w) return;
    if (w.fullScreenChanged)    w.fullScreenChanged.connect(function() { apply(); });
    if (w.minimizedChanged)     w.minimizedChanged.connect(function() { apply(); });
    // maximize/restore changes the frame geometry, so frameGeometryChanged already
    // catches it; maximizedChanged (when present) makes the response immediate.
    if (w.maximizedChanged)     w.maximizedChanged.connect(function() { apply(); });
    if (w.frameGeometryChanged) w.frameGeometryChanged.connect(function() { apply(); });
}

var initial = windows();
for (var i = 0; i < initial.length; i++)
    hook(initial[i]);

if (workspace.windowAdded)        workspace.windowAdded.connect(function(w) { hook(w); apply(); });
else if (workspace.clientAdded)   workspace.clientAdded.connect(function(w) { hook(w); apply(); });
if (workspace.windowRemoved)      workspace.windowRemoved.connect(function(w) { apply(w); });
else if (workspace.clientRemoved) workspace.clientRemoved.connect(function(w) { apply(w); });

apply();
