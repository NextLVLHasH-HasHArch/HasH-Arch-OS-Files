/*
 * MusicWave.qml — audio visualizer at bottom-center of the wallpaper.
 *
 * GPU-accelerated: bars are Qt Quick scene-graph Rectangles (rendered on the
 * GPU), NOT a CPU-rasterized Canvas. Reads the latest cava frame via the
 * executable DataSource (`cat`) — file:// XHR is broken in this Qt build.
 * Requires: `cava` + `systemctl --user start cava-wallpaper.service`.
 */
import QtQuick
import org.kde.plasma.plasma5support as P5Support

Item {
    id: vis

    property string dataFile: "/run/user/1001/cava-wallpaper.dat"
    property color  color1: "#7a2bff"   // bar bottom
    property color  color2: "#19e0ff"   // bar top
    property real   fps: 24
    property bool   paused: false
    property string colorMode: "level"     // level | cyan | rainbow | warm

    // bar colour for the current scheme + level (0..1) + bar index
    function barColor(level, index, n) {
        var lv = Math.min(1.0, level);
        switch (colorMode) {
        case "cyan":    return Qt.hsva(0.52, 0.80, 0.65 + lv * 0.35, 0.95);
        case "rainbow": return Qt.hsva((index % n) / Math.max(1, n), 0.85, 1.0, 0.95);
        case "warm":    return Qt.hsva(0.08 - lv * 0.08, 0.90, 1.0, 0.95);
        default:        return Qt.hsva(0.58 - lv * 0.5, 0.85, 1.0, 0.95);   // level
        }
    }

    // Live bottom-dock geometry (screen-local px) pushed by the wallpaperguard
    // KWin script. The flat centre row spans the dock; everything outside drops.
    property real   dockCenter: -1         // -1 => unknown, fall back to dropBars
    property real   dockWidth: 0
    property real   dockMargin: 0          // drops begin right at the dock's outer icons

    property int  barCount: 32
    property var  levels: []            // barCount values, 0..1
    property bool active: false

    opacity: active ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }

    P5Support.DataSource {
        id: feed
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            feed.disconnectSource(source);
            var raw = data["stdout"] || "";
            var parts = raw.split(";");
            var vals = [];
            var sum = 0;
            for (var i = 0; i < parts.length; i++) {
                var s = parts[i].trim();
                if (s.length === 0) continue;
                var v = Math.max(0, Math.min(100, parseInt(s, 10))) / 100.0;
                if (!isNaN(v)) {
                    v = Math.pow(v, 0.6);          // perceptual curve: quiet sounds move the bars too
                    vals.push(v); sum += v;
                }
            }
            if (vals.length === 0) { vis.active = false; return; }
            vis.barCount = vals.length;
            vis.levels = vals;
            vis.active = (sum / vals.length) > 0.012;
        }
    }

    Timer {
        interval: Math.max(16, 1000 / vis.fps)
        running: !vis.paused
        repeat: true
        onTriggered: feed.connectSource("cat " + vis.dataFile + " 2>/dev/null")
    }

    // Flat straight line of bars across the centre; at each end the baseline
    // drops STRAIGHT down (a straight diagonal, not a curve) to the screen
    // bottom, so the line frames the dock instead of arching over it.
    property real maxLen: 95               // longest bar (grows taller)
    property real lineOffset: 70           // flat-line baseline above the bottom panel (dropped another 5px)
    property real spanFrac: 1.0            // visualizer spans the full screen width, edge to edge
    property int  dropBars: 24             // outer N bars each side stand at the desktop bottom

    Item {
        id: bars
        anchors.fill: parent
        readonly property int n: vis.barCount
        readonly property real gap: 2
        readonly property real spanW: width * vis.spanFrac
        readonly property real bw: Math.max(2, spanW / n - gap)
        readonly property real step: bw + gap
        readonly property real startX: (width - n * step) / 2      // centred on screen
        readonly property real flatY: height - vis.lineOffset      // the flat baseline
        readonly property real bottomY: height                     // the bottom of the desktop

        // Number of flat bars on EACH side of the centre. Counting in whole bars
        // symmetrically (rather than a px threshold vs dockCenter) keeps the left
        // and right counts identical, so there's no 1-bar parity drift as the dock
        // grows/shrinks. -1 trims the one-bar overshoot over the dock edges.
        readonly property real centerIdx: (n - 1) / 2.0
        readonly property int  flatHalf: vis.dockWidth > 0
            ? Math.max(0, Math.round((vis.dockWidth / 2 + vis.dockMargin) / step))
            : Math.max(0, Math.round((n - 2 * vis.dropBars) / 2))   // fallback: fixed count

        Repeater {
            model: bars.n
            delegate: Rectangle {
                required property int index
                readonly property real level: (vis.levels[index] !== undefined) ? vis.levels[index] : 0
                readonly property real len: Math.max(2, level * vis.maxLen)
                // flat where the bar sits over the dock (symmetric bar count),
                // otherwise drop fully to the bottom. The flat middle grows as the
                // task manager grows and the side drops grow as it shrinks (and reverse).
                readonly property bool overDock:
                    Math.abs(index - bars.centerIdx) <= bars.flatHalf - 0.5
                readonly property real baseY: overDock ? bars.flatY : bars.bottomY
                width: bars.bw
                x: bars.startX + index * bars.step
                height: len
                y: baseY - len                                     // grows UPWARD from the baseline
                radius: width / 2
                antialiasing: true
                color: vis.barColor(level, index, bars.n)
                Behavior on height { NumberAnimation { duration: 38; easing.type: Easing.OutQuad } }
            }
        }
    }
}
