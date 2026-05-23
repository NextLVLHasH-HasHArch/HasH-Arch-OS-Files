/*
    SPDX-FileCopyrightText: 2011 Martin Gräßlin <mgraesslin@kde.org>
    SPDX-FileCopyrightText: 2012 Gregor Taetzner <gregor@freenet.de>
    SPDX-FileCopyrightText: 2012 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2013 2014 David Edmundson <davidedmundson@kde.org>
    SPDX-FileCopyrightText: 2014 Sebastian Kügler <sebas@kde.org>
    SPDX-FileCopyrightText: 2021 Mikel Johnson <mikel5764@gmail.com>
    SPDX-FileCopyrightText: 2021 Noah Davis <noahadvs@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import QtQuick.Templates as T
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.plasma.extras as PlasmaExtras

EmptyPage {
    id: root

    // Rounded iOS-folder-style popup: drop Plasma's dialog frame and draw our own
    // rounded dark box, so the launcher matches the desktop folders.
    leftPadding: Kirigami.Units.smallSpacing
    rightPadding: Kirigami.Units.smallSpacing
    topPadding: 0
    bottomPadding: Kirigami.Units.smallSpacing
    readonly property var appletInterface: kickoff

    function killDialogFrame() {
        const w = Window.window;
        if (w && w.hasOwnProperty("backgroundHints"))
            w.backgroundHints = 0;   // PlasmaCore.Dialog NoBackground (drops frame + square shadow)
        if (w && w.hasOwnProperty("color"))
            w.color = "transparent";
    }
    // Re-apply for a moment after the popup opens — the dialog frame/shadow can be
    // (re)applied a little after Window.window first becomes available, which is
    // what left the opaque black square around the rounded launcher.
    Timer {
        id: frameKiller; interval: 60; repeat: true
        property int n: 0
        onTriggered: { root.killDialogFrame(); if (++n > 10) stop(); }
    }
    onVisibleChanged: if (visible) { killDialogFrame(); frameKiller.n = 0; frameKiller.restart(); }
    Window.onWindowChanged: killDialogFrame()

    background: Rectangle {
        radius: 20
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.10, 0.11, 0.15, 0.97) }
            GradientStop { position: 1.0; color: Qt.rgba(0.04, 0.05, 0.08, 0.98) }
        }
        border.color: Qt.rgba(1, 1, 1, 0.12)
        border.width: 1
    }

    // Fixed launcher size that scales ONLY with the monitor resolution — it does
    // not stretch to fit content. Both dimensions derive from the screen's
    // VERTICAL resolution, so the launcher keeps one constant shape and simply
    // scales: bigger on a 1440p/4K panel, smaller on 720p, but never changes on a
    // given screen and never grows to fit content (content scrolls inside).
    readonly property int hashHeight: Math.round(Screen.height * 0.40)
    readonly property int hashWidth:  Math.round(Screen.height * 0.605)
    Layout.minimumWidth: hashWidth
    Layout.maximumWidth: hashWidth
    Layout.preferredWidth: hashWidth
    Layout.minimumHeight: hashHeight
    Layout.maximumHeight: hashHeight
    Layout.preferredHeight: hashHeight

    property alias normalPage: normalPage
    property bool blockingHoverFocus: true
    property var interceptedPosition: null

    /* NOTE: Important things to know about keyboard input handling:
     *
     * - Key events are passed up to parent items until the end is reached.
     * Be mindful of this when using `Keys.forwardTo`.
     *
     * - Keys defaults to BeforeItem while KeyNavigation defaults to AfterItem.
     *
     * - When Keys and KeyNavigation are using the same priority, it seems like
     * the one declared first in the QML file gets priority over the other.
     *
     * - Except for Keys.onPressed, all Keys.on*Pressed signals automatically
     * set `event.accepted = true`.
     *
     * - If you do `item.forceActiveFocus()` and `item` is a focus scope, the
     * children of `item` won't necessarily get focus. It seems like
     * `forceActiveFocus()` is better for forcing a specific thing to be focused
     * while KeyNavigation is better at passing focus down to children of the
     * thing you want to focus when dealing with focus scopes.
     *
     * - KeyNavigation uses BacktabFocusReason (TabFocusReason if mirrored) for left,
     * TabFocusReason (BacktabFocusReason if mirrored) for right,
     * BacktabFocusReason for up and TabFocusReason for down.
     *
     * - KeyNavigation does not seem to respect dynamic changes to focus chain
     * rules in the reverse direction, which can lead to confusing results.
     * It is therefore safer to use Keys for items whose position in the Tab
     * order must be changed on demand. (Tested with Qt 5.15.8 on X11.)
     */

    header: Header {
        id: header
        preferredNameAndIconWidth: normalPage.preferredSideBarWidth
        Binding {
            target: kickoff
            property: "header"
            value: header
            restoreMode: Binding.RestoreBinding
        }
    }

    contentItem: VerticalStackView {
        id: contentItemStackView
        focus: true
        movementTransitionsEnabled: true
        // Not using a component to prevent it from being destroyed
        initialItem: NormalPage {
            id: normalPage
            objectName: "normalPage"
        }

        Component {
            id: searchViewComponent
            KickoffListView {
                id: searchView
                objectName: "searchView"
                mainContentView: true
                // Forces the function be re-run every time runnerModel.count changes.
                // This is absolutely necessary to make the search view work reliably.
                model: kickoff.runnerModel.count ? kickoff.runnerModel.modelForRow(0) : null
                delegate: KickoffListDelegate {
                    width: view.availableWidth
                    isSearchResult: true
                }
                section.property: "group"
                activeFocusOnTab: true
                Keys.onTabPressed: event => {
                    kickoff.firstHeaderItem.forceActiveFocus(Qt.TabFocusReason);
                }
                Keys.onBacktabPressed: event => {
                    kickoff.lastHeaderItem.forceActiveFocus(Qt.BacktabFocusReason);
                }
                Keys.onUpPressed: event => {
                    kickoff.searchField.forceActiveFocus(Qt.BacktabFocusReason)
                }
                T.StackView.onActivated: {
                    kickoff.sideBar = null
                    kickoff.contentArea = searchView
                }

                Loader {
                    anchors.centerIn: searchView.view
                    width: searchView.view.width - (Kirigami.Units.gridUnit * 4)

                    active: searchView.view.count === 0
                    visible: active
                    asynchronous: true

                    sourceComponent: PlasmaExtras.PlaceholderMessage {
                        id: emptyHint

                        iconName: "edit-none"
                        opacity: 0
                        text: i18nc("@info:status", "No matches") // qmllint disable unqualified

                        Connections {
                            target: kickoff.runnerModel
                            function onQueryFinished() {
                                showAnimation.restart()
                            }
                        }

                        NumberAnimation {
                            id: showAnimation
                            duration: Kirigami.Units.longDuration
                            easing.type: Easing.OutCubic
                            property: "opacity"
                            target: emptyHint
                            to: 1
                        }
                    }
                }
            }
        }

        Connections {
            target: kickoff
            function onExpandedChanged() {
                if (!kickoff.expanded) {
                    root.blockingHoverFocus = true
                    root.interceptedPosition = null
                }
            }
        }

        Connections {
            target: blockHoverFocusHandler
            enabled: blockHoverFocusHandler.enabled && !root.interceptedPosition
            function onPointChanged() {
                root.interceptedPosition = blockHoverFocusHandler.point.position
            }
        }

        Connections {
            target: blockHoverFocusHandler
            enabled: blockHoverFocusHandler.enabled && root.interceptedPosition && root.blockingHoverFocus
            function onPointChanged() {
                if (blockHoverFocusHandler.point.position === root.interceptedPosition) {
                    return;
                }
                root.blockingHoverFocus = false
            }
        }

        HoverHandler {
            id: blockHoverFocusHandler
            enabled: !contentItemStackView.busy && (!root.interceptedPosition || root.blockingHoverFocus)
        }

        Keys.priority: Keys.AfterItem
        // This is here rather than root because events are implicitly forwarded
        // to parent items. Don't want to send multiple events to searchField.
        Keys.forwardTo: kickoff.searchField

        Connections {
            target: root.header
            function onSearchTextChanged() {
                if ((root.header as Header).searchText.length === 0 &&
                    contentItemStackView.currentItem.objectName !== "normalPage") {
                    root.blockingHoverFocus = true
                    contentItemStackView.reverseTransitions = true
                    contentItemStackView.replace(normalPage)
                } else if ((root.header as Header).searchText.length > 0) {
                    if (contentItemStackView.currentItem.objectName !== "searchView") {
                        contentItemStackView.reverseTransitions = false
                        contentItemStackView.replace(searchViewComponent)
                    } else {
                        root.blockingHoverFocus = true
                        root.interceptedPosition = null
                        contentItemStackView.contentItem.currentIndex = 0
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        rootModel.refresh();
        killDialogFrame();
    }
}
