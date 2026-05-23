/*
    SPDX-FileCopyrightText: 2013 Aurélien Gâteau <agateau@kde.org>
    SPDX-FileCopyrightText: 2014-2015 Eike Hein <hein@kde.org>
    SPDX-FileCopyrightText: 2021 Mikel Johnson <mikel5764@gmail.com>
    SPDX-FileCopyrightText: 2021 Noah Davis <noahadvs@gmail.com>
    SPDX-FileCopyrightText: 2024 ivan tkachenko <me@ratijas.tk>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound
pragma Singleton // NOTE: Singletons are shared between all instances of a plasmoid

import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import "code/tools.js" as Tools

Item {
    id: root

    property var actionList: null

    // Only one action menu can be open at a time, so this should be safe to use.
    property PlasmoidItem plasmoid: null

    // Runs hash-cat for our custom "Add to / Remove from group" actions.
    P5Support.DataSource {
        id: hashCat
        engine: "executable"
        connectedSources: []
        onNewData: (src, data) => hashCat.disconnectSource(src)
    }
    function hashRun(actionId, arg) {
        const parts = String(arg).split("::");
        const slug = parts[0];
        const desktop = parts.slice(1).join("::");
        const sub = actionId === "_hashAddTo" ? "tag-app" : "untag-app";
        hashCat.connectSource('/home/hash/.local/bin/hash-cat ' + sub
            + ' "' + desktop + '" "' + slug + '"');
    }

    // Not a QQC1 Menu. It's actually a custom QObject that uses a QMenu.
    readonly property PlasmaExtras.Menu menu: PlasmaExtras.Menu {
        id: menu

        visualParent: null
        placement: PlasmaExtras.Menu.BottomPosedLeftAlignedPopup
    }

    visible: false

    Instantiator {
        active: root.actionList !== null
        model: root.actionList
        delegate: menuItemComponent
        onObjectAdded: (index, object) => menu.addMenuItem(object)
        onObjectRemoved: (index, object) => menu.removeMenuItem(object)
    }

    Component {
        id: menuComponent

        PlasmaExtras.Menu {}
    }

    Component {
        id: menuItemComponent

        PlasmaExtras.MenuItem {
            id: menuItem

            required property var modelData
            readonly property PlasmaExtras.Menu subMenu: modelData.subActions
                ? menuComponent.createObject(this, { visualParent: action }) as PlasmaExtras.Menu
                : null

            text: modelData.text ?? ""
            enabled: modelData.type !== "title" && (modelData.enabled ?? true)
            separator: modelData.type === "separator"
            section: modelData.type === "title"
            icon: modelData.icon ?? null
            checkable: modelData.checkable ?? false
            checked: modelData.checked ?? false

            readonly property Instantiator __instantiator: Instantiator {
                active: menuItem.subMenu !== null
                model: menuItem.modelData.subActions
                delegate: menuItemComponent
                onObjectAdded: (index, object) => menuItem.subMenu.addMenuItem(object)
                onObjectRemoved: (index, object) => menuItem.subMenu.removeMenuItem(object)
            }

            onClicked: {
                // HasH-Arch custom group actions run hash-cat, not the kicker model
                if (modelData.actionId === "_hashAddTo" || modelData.actionId === "_hashRemoveFrom") {
                    root.hashRun(modelData.actionId, modelData.actionArgument);
                    if (root.plasmoid.hideOnWindowDeactivate) {
                        root.plasmoid.expanded = false
                    }
                    return;
                }
                const modelActionTriggered = Tools.triggerAction(
                    menu.visualParent.view.model,
                    menu.visualParent.index,
                    modelData.actionId,
                    modelData.actionArgument
                )
                // close early (if marked as such) to be more responsive to user input
                if (modelActionTriggered && root.plasmoid.hideOnWindowDeactivate) {
                    root.plasmoid.expanded = false
                }
            }
        }
    }
}
