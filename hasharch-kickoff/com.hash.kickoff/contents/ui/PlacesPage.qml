/*
 * HasH-Arch Places page — lists the BlackArch tools grouped BY FUNCTION
 * (Scanners, Web Application, Recon, ...). The tools are NoDisplay (hidden from
 * KRunner / All Applications), so this page reads them straight from
 * ~/.local/share/com.hash.kickoff/blackarch.json (produced by hash-blackarch.sh)
 * and launches them with `kioclient exec`, bypassing the NoDisplay flag.
 */
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Templates as T
import org.kde.plasma.components as PC3
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

BasePage {
    id: root

    readonly property string jsonPath: "/home/hash/.local/share/com.hash.kickoff/allapps.json"
    property var groups: []
    property string _last: ""

    ListModel { id: groupsModel }   // sidebar: { name }
    ListModel { id: itemsModel }    // content: { name, icon, exec, comment, file }

    P5Support.DataSource {
        id: exe
        engine: "executable"
        connectedSources: []
        onNewData: function(src, data) { exe.disconnectSource(src); }
    }
    // Console tools open a terminal that first runs `<tool> --help` (to teach what
    // it does) and then drops into a usable shell. GUI tools launch normally.
    function launch(item) {
        if (!item) return;
        if (item.terminal && item.bin && String(item.bin).length) {
            const bin = String(item.bin).replace(/'/g, "'\\''");
            exe.connectSource("konsole -e bash -c '" + bin
                + " --help; echo; echo \"──> You are now in a shell. Type the tool name to run it.\"; exec bash'");
        } else if (item.terminal) {
            // data/library package (no runnable binary) — show what it provides
            const nm = String(item.name).replace(/[^A-Za-z0-9._-]/g, "");
            exe.connectSource("konsole -e bash -c 'echo \"" + nm
                + ": data/library package (no command). Files it provides:\"; echo; pacman -Ql "
                + nm + " 2>/dev/null | grep -v \"/$\" | sed \"s/^[^ ]* //\"; echo; echo \"──> shell\"; exec bash'");
        } else if (item.file) {
            exe.connectSource('kioclient exec "' + item.file + '"');
        }
    }
    // promote a tool into an Applications group, then refresh Places (it leaves)
    function promote(file, slug) {
        if (!file || !slug) return;
        exe.connectSource('/home/hash/.local/bin/hash-cat promote "' + file + '" "' + slug + '"');
        promoteReload.restart();
    }
    Timer {
        id: promoteReload; interval: 2000; repeat: true
        property int n: 0
        onTriggered: { root._last = ""; root.reload(); n++; if (n > 6) { stop(); n = 0; } }
    }

    P5Support.DataSource {
        id: reader
        engine: "executable"
        connectedSources: []
        onNewData: function(src, data) {
            reader.disconnectSource(src);
            const txt = data["stdout"];
            if (!txt || txt === root._last) return;
            root._last = txt;
            try {
                root.groups = JSON.parse(txt).groups || [];
                groupsModel.clear();
                for (let i = 0; i < root.groups.length; i++)
                    groupsModel.append({ name: root.groups[i].name,
                                         gicon: root.groups[i].icon || "applications-other" });
                root.showGroup(sideBar2 ? sideBar2.currentIndex : 0);
            } catch (e) { console.log("PlacesPage parse error:", e); }
        }
    }
    function reload() { reader.connectSource("cat " + root.jsonPath + " 2>/dev/null"); }

    // custom desktop folders (populate the "Add to Desktop" submenu)
    property var customFolders: []
    P5Support.DataSource {
        id: custReader
        engine: "executable"; connectedSources: []
        onNewData: function(src, data) {
            custReader.disconnectSource(src);
            root.customFolders = (data["stdout"] || "").split("\n").filter(function(x){ return x.trim().length; });
        }
    }
    function loadCustom() { custReader.connectSource("/home/hash/.local/bin/hash-desktop list-custom"); }
    function addToDesktop(file, folder) {
        if (!file || !folder) return;
        exe.connectSource('/home/hash/.local/bin/hash-desktop add "' + file + '" "' + folder + '"');
    }
    function addToDesktopNew(file) {
        if (!file) return;
        exe.connectSource('/home/hash/.local/bin/hash-desktop new-and-add "' + file + '"');
        custLoadSoon.restart();
    }
    Timer { id: custLoadSoon; interval: 2500; onTriggered: root.loadCustom() }
    Component.onCompleted: { reload(); loadCustom(); }

    property ListView sideBar2: null
    function showGroup(idx) {
        itemsModel.clear();
        if (idx < 0 || idx >= root.groups.length) return;
        const items = root.groups[idx].items || [];
        for (let i = 0; i < items.length; i++) itemsModel.append(items[i]);
    }

    sideBarComponent: ListView {
        id: sideBar
        focus: true
        model: groupsModel
        currentIndex: 0
        Component.onCompleted: root.sideBar2 = sideBar
        onCurrentIndexChanged: root.showGroup(currentIndex)
        delegate: PC3.ItemDelegate {
            id: cat
            required property int index
            required property var model
            width: ListView.view.width
            text: model.name
            icon.name: model.gicon
            onClicked: sideBar.currentIndex = index
            highlighted: ListView.isCurrentItem
        }
    }

    contentAreaComponent: ListView {
        id: contentArea
        model: itemsModel
        focus: true
        clip: true
        QQC2.ScrollBar.vertical: QQC2.ScrollBar {}
        delegate: PC3.ItemDelegate {
            id: appItem
            required property var model
            width: ListView.view.width
            text: model.name
            icon.name: model.icon
            onClicked: root.launch(model)
            PC3.ToolTip.text: model.comment
            PC3.ToolTip.visible: hovered && model.comment.length > 0
            PC3.ToolTip.delay: 600
            // right-click a tool -> add it to an Applications group (promote: un-hide + tag)
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: { placeCtx.file = appItem.model.file; placeCtx.popup(); }
            }
        }
    }

    QQC2.Menu {
        id: placeCtx
        property string file: ""
        QQC2.Menu {
            id: addToAppsMenu
            title: i18n("Add to Applications")
            Instantiator {
                model: kickoff.hashGroups
                delegate: QQC2.MenuItem {
                    required property var modelData
                    text: modelData.name
                    onTriggered: root.promote(placeCtx.file, modelData.slug)
                }
                onObjectAdded: (index, object) => addToAppsMenu.insertItem(index, object)
                onObjectRemoved: (index, object) => addToAppsMenu.removeItem(object)
            }
        }
        // Add this app to a desktop iOS folder (NOT tied to a launcher category).
        QQC2.Menu {
            id: addToDesktopMenu
            title: i18n("Add to Desktop")
            QQC2.MenuItem {
                text: i18n("New folder…")
                icon.name: "folder-new"
                onTriggered: root.addToDesktopNew(placeCtx.file)
            }
            QQC2.MenuSeparator {}
            Instantiator {
                model: root.customFolders
                delegate: QQC2.MenuItem {
                    required property var modelData
                    text: modelData
                    icon.name: "folder"
                    onTriggered: root.addToDesktop(placeCtx.file, modelData)
                }
                onObjectAdded: (index, object) => addToDesktopMenu.insertItem(index + 2, object)
                onObjectRemoved: (index, object) => addToDesktopMenu.removeItem(object)
            }
        }
    }

    Binding {
        target: kickoff; property: "sideBar"; value: root.sideBarItem
        when: root.T.StackView.status === T.StackView.Active && root.visible
        restoreMode: Binding.RestoreBinding
    }
    Binding {
        target: kickoff; property: "contentArea"; value: root.contentAreaItem
        when: root.T.StackView.status === T.StackView.Active && root.visible
        restoreMode: Binding.RestoreBinding
    }
}
