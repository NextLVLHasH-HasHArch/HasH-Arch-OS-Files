/*
 * HasH-Arch Settings page — an in-launcher control panel. Categories on the left,
 * KCM/control shortcuts on the right. "Applications" hosts the (planned) custom
 * uninstaller that maps a program and ALL its files, even outside the package
 * manager. Launches via the executable DataSource.
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

    // [category] -> list of { name, icon, exec, comment }
    readonly property var sections: [
        { name: "Quick Settings", icon: "configure", items: [
            { name: "Wi-Fi & Network", icon: "network-wireless",  exec: "systemsettings kcm_networkmanagement", comment: "Connections" },
            { name: "Bluetooth",       icon: "network-bluetooth", exec: "systemsettings kcm_bluetooth",         comment: "Pair devices" },
            { name: "Display",         icon: "preferences-desktop-display", exec: "systemsettings kcm_kscreen",  comment: "Monitors & resolution" },
            { name: "Sound",           icon: "audio-volume-high", exec: "systemsettings kcm_pulseaudio",        comment: "Audio devices" },
            { name: "Power",           icon: "battery",           exec: "systemsettings kcm_powerdevilprofilesconfig", comment: "Energy saving" },
        ] },
        { name: "Appearance", icon: "preferences-desktop-theme", items: [
            { name: "Wallpaper",     icon: "preferences-desktop-wallpaper", exec: "systemsettings kcm_wallpaper",   comment: "Desktop background" },
            { name: "Global Theme",  icon: "preferences-desktop-theme-global", exec: "systemsettings kcm_lookandfeel", comment: "Look & feel" },
            { name: "Icons",         icon: "preferences-desktop-icons", exec: "systemsettings kcm_icons",            comment: "Icon theme" },
        ] },
        { name: "Desktop", icon: "preferences-desktop", items: [
            { name: "Music Visualizer", icon: "view-media-visualization", exec: "/home/hash/.local/bin/hash-visualizer-settings.sh", comment: "Enable/disable & colour scheme of the wallpaper audio visualizer" },
        ] },
        { name: "System", icon: "computer", items: [
            { name: "Users",        icon: "system-users",  exec: "systemsettings kcm_users",        comment: "User accounts" },
            { name: "Date & Time",  icon: "clock",         exec: "systemsettings kcm_clock",        comment: "" },
            { name: "About System", icon: "help-about",    exec: "systemsettings kcm_about-distro", comment: "HasH-Arch info" },
        ] },
        { name: "Software", icon: "applications-other", items: [
            { name: "Software Center",     icon: "system-software-install", exec: "/home/hash/.local/bin/hash-store", comment: "Browse, search & install apps and packages — no terminal" },
            { name: "System Updates",      icon: "system-software-update",  exec: "/home/hash/.local/bin/hash-store --updates", comment: "Update everything; asks for your password graphically (no terminal)" },
            { name: "Uninstall a Program", icon: "edit-delete",             exec: "/home/hash/.local/bin/hash-uninstaller", comment: "Map a program + ALL its files and remove it (incl. non-packaged)" },
        ] },
    ]

    ListModel { id: sectionsModel }
    ListModel { id: itemsModel }

    P5Support.DataSource {
        id: exe; engine: "executable"; connectedSources: []
        onNewData: function(src, d) { exe.disconnectSource(src); }
    }
    function run(cmd) { if (cmd && cmd.length) exe.connectSource(cmd); }

    function showSection(idx) {
        itemsModel.clear();
        if (idx < 0 || idx >= root.sections.length) return;
        const items = root.sections[idx].items || [];
        for (let i = 0; i < items.length; i++) itemsModel.append(items[i]);
    }
    Component.onCompleted: {
        for (let i = 0; i < root.sections.length; i++)
            sectionsModel.append({ name: root.sections[i].name, gicon: root.sections[i].icon });
        showSection(0);
    }

    sideBarComponent: ListView {
        id: sideBar
        focus: true
        model: sectionsModel
        currentIndex: 0
        onCurrentIndexChanged: root.showSection(currentIndex)
        delegate: PC3.ItemDelegate {
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
            required property var model
            width: ListView.view.width
            text: model.name
            icon.name: model.icon
            onClicked: root.run(model.exec)
            PC3.ToolTip.text: model.comment
            PC3.ToolTip.visible: hovered && model.comment.length > 0
            PC3.ToolTip.delay: 600
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
