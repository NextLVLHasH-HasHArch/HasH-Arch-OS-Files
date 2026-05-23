/*
 * MatrixRain.qml — self-contained animated "code rain".
 *
 * Pure QtQuick (Canvas only) with NO Plasma/KDE imports, so the exact same
 * file is reused by:
 *   - the Plasma desktop + lock screen (via the com.hash.matrixrain wallpaper plugin)
 *   - the SDDM "Sweet-Qt6" login theme
 *
 * Polish goals (iOS-weather feel): smooth motion, depth/parallax via per-column
 * speed + opacity, a tinted night-sky backdrop rather than flat black, and a
 * soft vignette.
 */
import QtQuick

Item {
    id: rain

    // ---- tunables (override per surface) ----
    property color skyTop:    "#02030c"   // night-sky tint, top
    property color skyBottom: "#01040a"   // night-sky tint, bottom (also the trail fade target)
    property color headColor: "#dafff3"   // bright leading glyph
    property color bodyColor: "#00ff85"   // trailing glyph color
    property int   glyphSize: 18           // px per glyph / column width
    property real  fps:       30           // capped for low CPU as a 24/7 wallpaper
    property real  trailFade: 0.10         // per-frame fade (lower = longer trails)
    property bool  paused:    false         // freeze when a fullscreen app is active
    property string glyphs: "01アイウエオカキクケコサシスセソタチツテトナニヌ{}[]<>/\\=;:+*!?$#01"

    // Night-sky base. The canvas trails fade toward skyBottom so they sit on a
    // tinted backdrop instead of pure black.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: rain.skyTop }
            GradientStop { position: 1.0; color: rain.skyBottom }
        }
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject
        renderStrategy: Canvas.Cooperative

        property var cols: []

        function rebuild() {
            var n = Math.max(1, Math.floor(width / rain.glyphSize));
            var arr = [];
            for (var i = 0; i < n; i++) {
                // depth: 0.35 (far, dim, slow) .. 1.0 (near, bright, fast)
                var depth = 0.35 + Math.random() * 0.65;
                arr.push({
                    x: Math.round(i * rain.glyphSize),
                    y: Math.random() * height,
                    speed: (0.6 + Math.random() * 1.4) * rain.glyphSize * depth / 6.0,
                    depth: depth
                });
            }
            cols = arr;
            var ctx = getContext("2d");
            if (ctx)
                ctx.clearRect(0, 0, width, height);
        }

        onPaint: {
            var ctx = getContext("2d");
            if (!ctx)
                return;

            // fade previous frame toward the night-sky tint -> motion trails
            ctx.globalAlpha = rain.trailFade;
            ctx.fillStyle = rain.skyBottom;
            ctx.fillRect(0, 0, width, height);

            ctx.font = "bold " + rain.glyphSize + "px monospace";
            ctx.textBaseline = "top";

            for (var i = 0; i < cols.length; i++) {
                var c = cols[i];
                var g = rain.glyphs.charAt(Math.floor(Math.random() * rain.glyphs.length));

                // body glyph, depth-dimmed
                ctx.globalAlpha = c.depth;
                ctx.fillStyle = rain.bodyColor;
                ctx.fillText(g, c.x, c.y);

                // bright head highlight on top
                ctx.globalAlpha = Math.min(1.0, c.depth + 0.3);
                ctx.fillStyle = rain.headColor;
                ctx.fillText(g, c.x, c.y);

                c.y += c.speed;
                if (c.y > height + Math.random() * 240)
                    c.y = -Math.random() * 200;
            }
            ctx.globalAlpha = 1.0;
        }

        onWidthChanged: rebuild()
        onHeightChanged: rebuild()
        Component.onCompleted: rebuild()
    }

    Timer {
        interval: Math.max(16, 1000 / rain.fps)
        running: rain.visible && !rain.paused
        repeat: true
        onTriggered: canvas.requestPaint()
    }

    // Soft vignette top + bottom for an iOS-weather sense of depth.
    Rectangle {
        anchors.fill: parent
        z: 1
        gradient: Gradient {
            GradientStop { position: 0.0;  color: "#40000000" }
            GradientStop { position: 0.30; color: "#00000000" }
            GradientStop { position: 0.82; color: "#00000000" }
            GradientStop { position: 1.0;  color: "#66000000" }
        }
    }
}
