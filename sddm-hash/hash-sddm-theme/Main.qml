/*
    HasH SDDM theme — Main.qml.
    Based on Breeze's Main.qml (org.kde.breeze.components, Kirigami.Units, full
    StackView/user-list/session/power/virtual-keyboard/keyboard-layout/
    accessibility behaviour) with the HasH features ported in:
      * matrixrain WeatherScene wallpaper (components/WeatherScene.qml) reading
        /var/lib/hash/weather.json, drawing the desktop weather block
        (showClock + showInfo) so it is the only clock;
      * login form shown on the primary display only;
      * no "Desktop Session" label (SessionButton hidden, currentIndex kept);
      * 2FA password->code slide lives in Login.qml.

    SPDX-FileCopyrightText: 2016 David Edmundson <davidedmundson@kde.org>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import Qt5Compat.GraphicalEffects

import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator
import org.kde.kirigami as Kirigami

import org.kde.breeze.components

import "components"

Item {
    id: root

    // If we're using software rendering, draw outlines instead of shadows
    // See https://bugs.kde.org/show_bug.cgi?id=398317
    readonly property bool softwareRendering: GraphicsInfo.api === GraphicsInfo.Software

    Kirigami.Theme.colorSet: Kirigami.Theme.Complementary
    Kirigami.Theme.inherit: false

    width: 1600
    height: 900

    property string notificationMessage

    LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    KeyboardIndicator.KeyState {
        id: capsLockState
        key: Qt.Key_CapsLock
    }

    // HasH live weather background — the SAME GPU-shader WeatherScene the desktop
    // and lock screen use. The greeter runs as the `sddm` user and cannot read
    // ~/.config, so location/condition/temperature come from
    // /var/lib/hash/weather.json (written by hash-weather-sync from the user's
    // desktop matrixrain config). If the file is missing the WeatherScene falls
    // back to its own IP geolocation. Drawn on every screen.
    WeatherScene {
        id: wallpaper
        anchors.fill: parent
        units: "metric"
        forceCondition: "auto"   // overridden by the synced condition when present
        showInfo: true
        // Draw the integrated desktop block (time, date, location, temperature)
        // on every screen. This is the single clock — Breeze's Clock below is
        // hidden so the matrixrain block is the only one.
        showClock: true

        function loadSharedConfig() {
            var xhr = new XMLHttpRequest();
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return;
                if (xhr.status !== 200 && xhr.status !== 0)
                    return;   // file absent -> keep IP-geolocation fallback
                try {
                    var c = JSON.parse(xhr.responseText);
                    if (c.latitude  !== undefined) wallpaper.fixedLatitude  = c.latitude;
                    if (c.longitude !== undefined) wallpaper.fixedLongitude = c.longitude;
                    if (c.units)        wallpaper.units        = c.units;
                    if (c.locationName) { wallpaper.locationName = c.locationName;
                                          wallpaper.cachedPlace  = c.locationName; }
                    if (c.condition)    wallpaper.forceCondition    = c.condition;
                    if (c.temperature !== undefined) wallpaper.cachedTemperature = c.temperature;
                } catch (e) { console.log("weather.json parse error:", e); }
            };
            xhr.open("GET", "file:///var/lib/hash/weather.json");
            xhr.send();
        }
        Component.onCompleted: loadSharedConfig()
        // hash-weather-sync refreshes the file ~every 15 min; re-read while shown
        Timer { interval: 300000; running: true; repeat: true
                onTriggered: wallpaper.loadSharedConfig() }
    }

    // HasH: mouse-move / key blur, like Plasma's WallpaperFader. When the login
    // UI is idle (uiVisible false) the WeatherScene is sharp; as soon as the user
    // moves the mouse or types (loginScreenRoot.uiVisible becomes true) we fade in
    // a blurred copy of the wallpaper behind the form. GPU-cheap: a single cached
    // ShaderEffectSource of the live WeatherScene fed into FastBlur, with only the
    // overlay opacity animated (the source itself stays live so the weather keeps
    // animating underneath).
    ShaderEffectSource {
        id: wallpaperSource
        anchors.fill: parent
        sourceItem: wallpaper
        live: true
        hideSource: false
        visible: false   // only consumed by the FastBlur below
    }
    FastBlur {
        id: wallpaperBlur
        anchors.fill: parent
        source: wallpaperSource
        radius: 64
        cached: false
        // Sharp when idle, blurred once the login UI is shown.
        opacity: loginScreenRoot.uiVisible ? 1.0 : 0.0
        visible: opacity > 0
        Behavior on opacity {
            OpacityAnimator {
                duration: Kirigami.Units.veryLongDuration
                easing.type: Easing.InOutQuad
            }
        }
        // Subtle darkening tied to the blur, so the form text always reads.
        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: 0.28
        }
    }

    RejectPasswordAnimation {
        id: rejectPasswordAnimation
        target: mainStack
    }

    MouseArea {
        id: loginScreenRoot
        anchors.fill: parent

        // Show the login form ONLY on the primary screen; other screens get just
        // the WeatherScene wallpaper. `primaryScreen` is a context property set
        // by the SDDM greeter per window; guard for test-mode where it may be
        // undefined.
        visible: (typeof primaryScreen === "undefined") || primaryScreen

        property bool uiVisible: true
        property bool blockUI: mainStack.depth > 1 || userListComponent.mainPasswordBox.text.length > 0 || inputPanel.keyboardActive

        hoverEnabled: true
        drag.filterChildren: true
        onPressed: uiVisible = true;
        onPositionChanged: uiVisible = true;
        onUiVisibleChanged: {
            if (blockUI) {
                fadeoutTimer.running = false;
            } else if (uiVisible) {
                fadeoutTimer.restart();
            }
        }
        onBlockUIChanged: {
            if (blockUI) {
                fadeoutTimer.running = false;
                uiVisible = true;
            } else {
                fadeoutTimer.restart();
            }
        }

        Keys.onPressed: event => {
            uiVisible = true;
            event.accepted = false;
        }

        //takes one full minute for the ui to disappear
        Timer {
            id: fadeoutTimer
            running: true
            interval: 60000
            onTriggered: {
                if (!loginScreenRoot.blockUI) {
                    userListComponent.mainPasswordBox.showPassword = false;
                    loginScreenRoot.uiVisible = false;
                }
            }
        }

        // Breeze's clock, hidden: the WeatherScene draws the desktop-matching
        // time/date/location/temperature block on every screen instead.
        Clock {
            id: clock
            visible: false
            anchors.horizontalCenter: parent.horizontalCenter
            y: (userListComponent.userList.y + mainStack.y)/2 - height/2
            Layout.alignment: Qt.AlignBaseline
        }

        QQC2.StackView {
            id: mainStack
            anchors {
                left: parent.left
                right: parent.right
            }
            height: root.height + Kirigami.Units.gridUnit * 3

            // this isn't implicit, otherwise items still get processed for the scenegraph
            visible: opacity > 0

            // If true (depends on the style and environment variables), hover events are always accepted
            // and propagation stopped. This means the parent MouseArea won't get them and the UI won't be shown.
            // Disable capturing those events while the UI is hidden to avoid that, while still passing events otherwise.
            // One issue is that while the UI is visible, mouse activity won't keep resetting the timer, but when it
            // finally expires, the next event should immediately set uiVisible = true again.
            hoverEnabled: loginScreenRoot.uiVisible ? undefined : false

            focus: true //StackView is an implicit focus scope, so we need to give this focus so the item inside will have it

            Timer {
                //SDDM has a bug in 0.13 where even though we set the focus on the right item within the window, the window doesn't have focus
                //it is fixed in 6d5b36b28907b16280ff78995fef764bb0c573db which will be 0.14
                //we need to call "window->activate()" *After* it's been shown. We can't control that in QML so we use a shoddy timer
                //it's been this way for all Plasma 5.x without a huge problem
                running: true
                repeat: false
                interval: 200
                onTriggered: mainStack.forceActiveFocus()
            }

            initialItem: Login {
                id: userListComponent
                userListModel: userModel
                loginScreenUiVisible: loginScreenRoot.uiVisible
                userListCurrentIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
                lastUserName: userModel.lastUser
                showUserList: {
                    if (!userListModel.hasOwnProperty("count")
                        || !userListModel.hasOwnProperty("disableAvatarsThreshold")) {
                        return false
                    }

                    if (userListModel.count === 0 ) {
                        return false
                    }

                    if (userListModel.hasOwnProperty("containsAllUsers") && !userListModel.containsAllUsers) {
                        return false
                    }

                    return userListModel.count <= userListModel.disableAvatarsThreshold
                }

                notificationMessage: {
                    const parts = [];
                    if (capsLockState.locked) {
                        parts.push(i18ndc("plasma-desktop-sddm-theme", "@info:status",  "Caps Lock is on"));
                    }
                    if (root.notificationMessage) {
                        parts.push(root.notificationMessage);
                    }
                    return parts.join(" • ");
                }

                actionItemsVisible: !inputPanel.keyboardActive
                actionItems: [
                    ActionButton {
                        icon.name: "system-hibernate"
                        text: i18ndc("plasma-desktop-sddm-theme", "Suspend to disk", "Hibernate")
                        onClicked: sddm.hibernate()
                        enabled: sddm.canHibernate
                    },
                    ActionButton {
                        icon.name: "system-suspend"
                        text: i18ndc("plasma-desktop-sddm-theme", "@action:button Suspend to RAM", "Sleep")
                        onClicked: sddm.suspend()
                        enabled: sddm.canSuspend
                    },
                    ActionButton {
                        icon.name: "system-reboot"
                        text: i18ndc("plasma-desktop-sddm-theme", "@action:button", "Restart")
                        onClicked: sddm.reboot()
                        enabled: sddm.canReboot
                    },
                    ActionButton {
                        icon.name: "system-shutdown"
                        text: i18ndc("plasma-desktop-sddm-theme", "@action:button", "Shut Down")
                        onClicked: sddm.powerOff()
                        enabled: sddm.canPowerOff
                    },
                    ActionButton {
                        icon.name: "system-user-prompt"
                        text: i18ndc("plasma-desktop-sddm-theme", "@action:button For switching to a username and password prompt", "Other…")
                        onClicked: mainStack.push(userPromptComponent)
                        visible: !userListComponent.showUsernamePrompt
                    }]

                onLoginRequest: {
                    root.notificationMessage = ""
                    sddm.login(username, password, sessionButton.currentIndex)
                }
            }

            Behavior on opacity {
                OpacityAnimator {
                    duration: Kirigami.Units.longDuration
                }
            }

            readonly property real zoomFactor: 1.5

            popEnter: Transition {
                ScaleAnimator {
                    from: mainStack.zoomFactor
                    to: 1
                    duration: Kirigami.Units.veryLongDuration
                    easing.type: Easing.OutCubic
                }
                OpacityAnimator {
                    from: 0
                    to: 1
                    duration: Kirigami.Units.veryLongDuration
                    easing.type: Easing.OutCubic
                }
            }

            popExit: Transition {
                ScaleAnimator {
                    from: 1
                    to: 1 / mainStack.zoomFactor
                    duration: Kirigami.Units.veryLongDuration
                    easing.type: Easing.OutCubic
                }
                OpacityAnimator {
                    from: 1
                    to: 0
                    duration: Kirigami.Units.veryLongDuration
                    easing.type: Easing.OutCubic
                }
            }

            pushEnter: Transition {
                ScaleAnimator {
                    from: 1 / mainStack.zoomFactor
                    to: 1
                    duration: Kirigami.Units.veryLongDuration
                    easing.type: Easing.OutCubic
                }
                OpacityAnimator {
                    from: 0
                    to: 1
                    duration: Kirigami.Units.veryLongDuration
                    easing.type: Easing.OutCubic
                }
            }

            pushExit: Transition {
                ScaleAnimator {
                    from: 1
                    to: mainStack.zoomFactor
                    duration: Kirigami.Units.veryLongDuration
                    easing.type: Easing.OutCubic
                }
                OpacityAnimator {
                    from: 1
                    to: 0
                    duration: Kirigami.Units.veryLongDuration
                    easing.type: Easing.OutCubic
                }
            }
        }

        VirtualKeyboardLoader {
            id: inputPanel

            z: 1

            screenRoot: root
            mainStack: mainStack
            mainBlock: userListComponent
            passwordField: userListComponent.mainPasswordBox
        }

        Component {
            id: userPromptComponent
            Login {
                showUsernamePrompt: true
                notificationMessage: root.notificationMessage
                loginScreenUiVisible: loginScreenRoot.uiVisible
                fontSize: Kirigami.Theme.defaultFont.pointSize + 2

                // using a model rather than a QObject list to avoid QTBUG-75900
                userListModel: ListModel {
                    ListElement {
                        name: ""
                        icon: ""
                    }
                    Component.onCompleted: {
                        // as we can't bind inside ListElement
                        setProperty(0, "name", i18ndc("plasma-desktop-sddm-theme", "@info:usagetip", "Type in Username and Password"));
                        setProperty(0, "icon", Qt.resolvedUrl("faces/.face.icon"))
                    }
                }

                onLoginRequest: {
                    root.notificationMessage = ""
                    sddm.login(username, password, sessionButton.currentIndex)
                }

                actionItemsVisible: !inputPanel.keyboardActive
                actionItems: [
                    ActionButton {
                        icon.name: "system-suspend"
                        text: i18ndc("plasma-desktop-sddm-theme", "@action:button Suspend to RAM", "Sleep")
                        onClicked: sddm.suspend()
                        enabled: sddm.canSuspend
                    },
                    ActionButton {
                        icon.name: "system-reboot"
                        text: i18ndc("plasma-desktop-sddm-theme", "@action:button", "Restart")
                        onClicked: sddm.reboot()
                        enabled: sddm.canReboot
                    },
                    ActionButton {
                        icon.name: "system-shutdown"
                        text: i18ndc("plasma-desktop-sddm-theme", "@action:button", "Shut Down")
                        onClicked: sddm.powerOff()
                        enabled: sddm.canPowerOff
                    },
                    ActionButton {
                        icon.name: "system-user-list"
                        text: i18ndc("plasma-desktop-sddm-theme", "@action:button", "List Users")
                        onClicked: mainStack.pop()
                    }
                ]
            }
        }

        // Note: Containment masks stretch clickable area of their buttons to
        // the screen edges, essentially making them adhere to Fitts's law.
        // Due to virtual keyboard button having an icon, buttons may have
        // different heights, so fillHeight is required.
        RowLayout {
            id: footer
            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
                margins: Kirigami.Units.smallSpacing
            }
            spacing: Kirigami.Units.smallSpacing

            Behavior on opacity {
                OpacityAnimator {
                    duration: Kirigami.Units.longDuration
                }
            }

            PlasmaComponents3.ToolButton {
                id: virtualKeyboardButton

                text: i18ndc("plasma-desktop-sddm-theme", "Button to show/hide virtual keyboard", "Virtual Keyboard")
                icon.name: inputPanel.keyboardActive ? "input-keyboard-virtual-on" : "input-keyboard-virtual-off"
                onClicked: {
                    // Otherwise the password field loses focus and virtual keyboard
                    // keystrokes get eaten
                    userListComponent.mainPasswordBox.forceActiveFocus();
                    inputPanel.showHide()
                }
                visible: inputPanel.status === Loader.Ready

                Layout.fillHeight: true
                containmentMask: Item {
                    parent: virtualKeyboardButton
                    anchors.fill: parent
                    anchors.leftMargin: -footer.anchors.margins
                    anchors.bottomMargin: -footer.anchors.margins
                }
            }

            KeyboardButton {
                id: keyboardButton

                onKeyboardLayoutChanged: {
                    // Otherwise the password field loses focus and virtual keyboard
                    // keystrokes get eaten
                    userListComponent.mainPasswordBox.forceActiveFocus();
                }

                Layout.fillHeight: true
                containmentMask: Item {
                    parent: keyboardButton
                    anchors.fill: parent
                    anchors.leftMargin: virtualKeyboardButton.visible ? 0 : -footer.anchors.margins
                    anchors.bottomMargin: -footer.anchors.margins
                }
            }

            // HasH: hidden per design — no "Desktop Session: Plasma (Wayland)"
            // label. Kept (not deleted) so sddm.login() still has a valid
            // currentIndex (the default/last session is used).
            SessionButton {
                id: sessionButton
                visible: false

                onSessionChanged: {
                    userListComponent.mainPasswordBox.forceActiveFocus();
                }

                Layout.fillHeight: true
            }

            Item {
                Layout.fillWidth: true
            }

            Battery {}
        }
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            notificationMessage = i18ndc("plasma-desktop-sddm-theme", "@info:status", "Login Failed")
            footer.enabled = true
            mainStack.enabled = true
            userListComponent.userList.opacity = 1
            rejectPasswordAnimation.start()
        }
        function onLoginSucceeded() {
            //note SDDM will kill the greeter at some random point after this
            //there is no certainty any transition will finish, it depends on the time it
            //takes to complete the init
            mainStack.opacity = 0
            footer.opacity = 0
        }
    }

    onNotificationMessageChanged: {
        if (notificationMessage) {
            notificationResetTimer.start();
        }
    }

    Timer {
        id: notificationResetTimer
        interval: 3000
        onTriggered: notificationMessage = ""
    }
}
