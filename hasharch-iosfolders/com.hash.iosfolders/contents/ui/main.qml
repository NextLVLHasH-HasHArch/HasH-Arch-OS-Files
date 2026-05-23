/*
 * iOS Folder — one draggable desktop folder for a single app group.
 * Add one widget per group (Games, Media, ...) and position them independently.
 * Compact = the iOS folder tile; clicking opens a popup grid of the group's apps.
 * Reads ~/.local/share/com.hash.iosfolders/folders.json via `cat`, live-reloading
 * so Steam shortcuts / new games appear in the matching folder automatically.
 */
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root
    preferredRepresentation: compactRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    readonly property string manifestPath: "/home/hash/.local/share/com.hash.iosfolders/folders.json"
    readonly property string groupName: Plasmoid.configuration.group
    property var groups: []
    property string _last: ""

    readonly property var group: {
        // match the configured group against a folder by name OR slug, case-insensitive,
        // so widgets configured with a short name (e.g. "Internet") still resolve.
        var key = (groupName || "").toLowerCase();
        for (var i = 0; i < groups.length; i++) {
            var g = groups[i];
            if (g.name === groupName || g.slug === groupName
                || (g.name && g.name.toLowerCase() === key)
                || (g.slug && g.slug.toLowerCase() === key))
                return g;
        }
        return { "name": groupName, "icon": "folder", "items": [] };
    }
    readonly property var items: group.items || []

    P5Support.DataSource {
        id: exe
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) { exe.disconnectSource(source); }
    }
    function launch(file) {
        if (file && file.length)
            exe.connectSource('kioclient exec "' + file + '"');
    }

    P5Support.DataSource {
        id: reader
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            reader.disconnectSource(source);
            var txt = data["stdout"];
            if (txt && txt !== root._last) {
                try {
                    root.groups = JSON.parse(txt).groups || [];
                    root._last = txt;
                } catch (e) { console.log("iosfolders parse error:", e); }
            }
        }
    }
    function reload() { reader.connectSource("cat " + root.manifestPath); }
    Timer { interval: 4000; running: true; repeat: true; onTriggered: root.reload() }
    Component.onCompleted: reload()

    // Remove an app from the desktop: delete its on-desktop shortcut (the entry
    // in the scanned dir, never the system file it points to), and our generated
    // copy if it's a fixed Steam shortcut. Then rebuild the manifest.
    Timer { id: reloadSoon; interval: 2000; onTriggered: root.reload() }
    function removeItem(it) {
        if (!it || !it.file) return;
        // Folders are tag-based, so removing an app = UNTAG it from THIS group.
        // hash-cat then rebuilds the manifest, removing just this one app from this
        // one folder (the old code rebuilt the whole manifest and wiped the folder).
        var slug = root.group.slug || root.groupName;
        var f = String(it.file).replace(/'/g, "'\\''");
        var s = String(slug).replace(/'/g, "'\\''");
        if (it.custom)   // custom desktop folder -> drop from custom.json
            exe.connectSource("/home/hash/.local/bin/hash-desktop remove '" + f + "' '" + s + "'");
        else             // category folder -> untag from the launcher group
            exe.connectSource("/home/hash/.local/bin/hash-cat untag-app '" + f + "' '" + s + "'");
        reloadSoon.restart();
    }

    // Add an app to THIS folder: pick a .desktop, tag it to this group (hash-cat).
    function addApp() {
        var slug = String(root.group.slug || root.groupName).replace(/'/g, "'\\''");
        exe.connectSource("f=$(kdialog --title 'Add application' --getopenfilename /usr/share/applications '*.desktop') && "
            + "[ -n \"$f\" ] && /home/hash/.local/bin/hash-cat tag-app \"$f\" '" + slug + "'");
        reloadSoon.restart();
    }
    // Remove an app from THIS folder: choose from a radiolist of its apps, untag it.
    function removeApp() {
        var slug = String(root.group.slug || root.groupName).replace(/'/g, "'\\''");
        var args = "";
        for (var i = 0; i < root.items.length; i++) {
            var it = root.items[i];
            args += " \"" + String(it.file).replace(/"/g, '\\"') + "\""
                  + " \"" + String(it.name).replace(/"/g, '\\"') + "\" off";
        }
        if (!args.length) return;
        exe.connectSource("sel=$(kdialog --title 'Remove application' --radiolist 'Remove which app from this folder?'"
            + args + ") && [ -n \"$sel\" ] && /home/hash/.local/bin/hash-cat untag-app \"$sel\" '" + slug + "'");
        reloadSoon.restart();
    }

    // Desktop right-click menu for this folder. No "Enter Edit Mode" — the build is
    // fixed; the folder manages its own apps (add/remove), and can be configured or
    // deleted. (The shell's standard edit-mode action is suppressed by locking the
    // desktop containment in the shipped layout; widgets + tray stay editable.)
    Plasmoid.contextualActions: [
        Kirigami.Action {
            text: i18n("Add application…"); icon.name: "list-add"
            onTriggered: root.addApp()
        },
        Kirigami.Action {
            text: i18n("Remove application…"); icon.name: "list-remove"
            enabled: root.items.length > 0
            onTriggered: root.removeApp()
        },
        Kirigami.Action { separator: true },
        Kirigami.Action {
            text: i18n("Configure iOS Folder…"); icon.name: "configure"
            onTriggered: { var a = Plasmoid.internalAction("configure"); if (a) a.trigger(); }
        },
        Kirigami.Action {
            text: i18n("Delete iOS Folder"); icon.name: "edit-delete"
            onTriggered: { var a = Plasmoid.internalAction("remove"); if (a) a.trigger(); }
        }
    ]

    toolTipMainText: root.groupName
    toolTipSubText: root.items.length + " apps"

    // ---- compact: the iOS folder tile (draggable on the desktop) ----
    compactRepresentation: Item {
        implicitWidth: 104
        implicitHeight: 126

        Rectangle {
            id: tray
            width: 96; height: 96
            anchors.horizontalCenter: parent.horizontalCenter
            radius: 22
            color: Qt.rgba(1, 1, 1, mouse.containsMouse ? 0.26 : 0.18)
            border.color: Qt.rgba(1, 1, 1, 0.22)
            border.width: 1
            Behavior on color { ColorAnimation { duration: 120 } }
            scale: mouse.pressed ? 0.92 : 1.0
            Behavior on scale { NumberAnimation { duration: 90 } }

            GridLayout {                       // 2x2 mini preview
                anchors.centerIn: parent
                columns: 2
                rowSpacing: 6; columnSpacing: 6
                Repeater {
                    model: Math.min(4, root.items.length)
                    delegate: Kirigami.Icon {
                        required property int index
                        implicitWidth: 30; implicitHeight: 30
                        source: root.items[index].icon
                    }
                }
            }
            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.expanded = !root.expanded
            }
        }

        PC3.Label {
            anchors.top: tray.bottom
            anchors.topMargin: 4
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.groupName
            color: "white"
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            style: Text.Outline
            styleColor: Qt.rgba(0, 0, 0, 0.6)
        }
    }

    // ---- full: popup grid of the group's apps (single rounded dark box) ----
    fullRepresentation: Item {
        readonly property int cols: Math.min(4, Math.max(1, root.items.length))
        readonly property int rowsN: Math.ceil(Math.max(1, root.items.length) / cols)
        Layout.minimumWidth: cols * 94 + 36
        Layout.minimumHeight: rowsN * 98 + 64
        Layout.preferredWidth: Layout.minimumWidth
        Layout.preferredHeight: Layout.minimumHeight

        // Strip Plasma's popup-dialog frame so only our rounded box shows. The
        // applet's NoBackground hint doesn't cover the popup window, so set the
        // dialog window's own backgroundHints to NoBackground (0) directly.
        function killDialogFrame() {
            var w = Window.window;
            if (w && w.hasOwnProperty("backgroundHints"))
                w.backgroundHints = 0;          // PlasmaCore.Dialog NoBackground
        }
        Component.onCompleted: killDialogFrame()
        onVisibleChanged: if (visible) killDialogFrame()
        Window.onWindowChanged: killDialogFrame()

        Rectangle {
            id: popupBox
            anchors.fill: parent
            radius: 26
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0.10, 0.11, 0.15, 0.97) }
                GradientStop { position: 1.0; color: Qt.rgba(0.04, 0.05, 0.08, 0.98) }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            PC3.Label {
                text: root.groupName
                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 3
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }

            GridView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                cellWidth: 94; cellHeight: 98
                clip: true
                model: root.items
                delegate: Item {
                    width: 96; height: 100
                    required property var modelData
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 4
                        Kirigami.Icon {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 52; implicitHeight: 52
                            source: modelData.icon
                        }
                        PC3.Label {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 88
                            text: modelData.name
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                    }
                    TapHandler { onTapped: { root.launch(modelData.file); root.expanded = false; } }
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: { ctxMenu.target = modelData; ctxMenu.popup(); }
                    }
                    HoverHandler { id: hh }
                    Rectangle {
                        anchors.fill: parent
                        z: -1; radius: 12
                        color: Qt.rgba(1, 1, 1, hh.hovered ? 0.12 : 0)
                    }
                }
            }
        }

        QQC2.Menu {
            id: ctxMenu
            property var target: null
            QQC2.MenuItem {
                text: i18n("Remove from desktop")
                icon.name: "edit-delete"
                onTriggered: root.removeItem(ctxMenu.target)
            }
        }
    }
}
