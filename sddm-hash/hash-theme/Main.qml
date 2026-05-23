/*
 *   Copyright 2016 David Edmundson <davidedmundson@kde.org>
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU Library General Public License as
 *   published by the Free Software Foundation; either version 2 or
 *   (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details
 *
 *   You should have received a copy of the GNU Library General Public
 *   License along with this program; if not, write to the
 *   Free Software Foundation, Inc.,
 *   51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */
 
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects

import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.components as PlasmaComponents
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
    property string clock_color: "#fff"

    LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    Plasma5Support.DataSource {
        id: keystateSource
        engine: "keystate"
        connectedSources: "Caps Lock"
    }

    // Live weather background — same WeatherScene used by the desktop and lock
    // screen. Greeter runs as the sddm user (no access to ~/.config), so it
    // resolves location from the baked-in city, falling back to IP geolocation.
    // Live weather background — the SAME GPU-shader WeatherScene the desktop uses
    // (real lunar phase, clouds, etc.). The greeter runs as the `sddm` user and
    // cannot read ~/.config, so the location/condition/temperature are NOT
    // hardcoded: they come from /var/lib/hash/weather.json, which hash-weather-sync
    // writes from the USER's desktop matrixrain config. If the file is missing the
    // WeatherScene falls back to its own IP geolocation.
    WeatherScene {
        id: wallpaper
        anchors.fill: parent
        units: "metric"
        forceCondition: "auto"   // overridden by the synced condition when present
        showInfo: true
        // Draw the SAME integrated block the desktop shows (time, date, location,
        // then temperature) on EVERY screen. The Sweet theme's own clock is hidden
        // below so this is the single, desktop-matching info block.
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

    MouseArea {
        id: loginScreenRoot
        anchors.fill: parent

        // Show the login form ONLY on the primary screen; other screens get just
        // the wallpaper (the WeatherScene sibling above stays visible everywhere).
        // `primaryScreen` is a context property set by the SDDM greeter per window;
        // guard for test-mode where it may be undefined.
        visible: (typeof primaryScreen === "undefined") || primaryScreen

        property bool uiVisible: true
        property bool blockUI: mainStack.depth > 1 || userListComponent.mainPasswordBox.text.length > 0 || inputPanel.keyboardActive || config.type != "image"

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

        Keys.onPressed: {
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
                    loginScreenRoot.uiVisible = false;
                }
            }
        }

        // Matched to the Plasma "Sweet" lock screen: clock centered above the
        // login form, with a drop shadow, instead of the bottom-right corner.
        DropShadow {
            id: clockShadow
            anchors.fill: clock
            source: clock
            visible: false   // Sweet clock hidden; WeatherScene draws the info block
            horizontalOffset: 1
            verticalOffset: 1
            radius: 6
            samples: 14
            spread: 0.3
            color: "black"
        }

        Clock {
            id: clock
            property Item shadow: clockShadow
            anchors.horizontalCenter: parent.horizontalCenter
            y: (userListComponent.userList.y + mainStack.y) / 2 - height / 2
            visible: false   // hidden: the WeatherScene draws the desktop-matching time/date/location/temp block on all screens
        }


        StackView {
            id: mainStack
            anchors.left: parent.left
            height: root.height
            width: parent.width / 3

            focus: true //StackView is an implicit focus scope, so we need to give this focus so the item inside will have it

            Timer {
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
                    if ( !userListModel.hasOwnProperty("count")
                    || !userListModel.hasOwnProperty("disableAvatarsThreshold"))
                        return (userList.y + mainStack.y) > 0

                    if ( userListModel.count == 0 ) return false

                    return userListModel.count <= userListModel.disableAvatarsThreshold && (userList.y + mainStack.y) > 0
                }

                notificationMessage: {
                    var text = ""
                    if (keystateSource.data["Caps Lock"]["Locked"]) {
                        text += i18nd("plasma_lookandfeel_org.kde.lookandfeel","Caps Lock is on")
                        if (root.notificationMessage) {
                            text += " • "
                        }
                    }
                    text += root.notificationMessage
                    return text
                }

                actionItems: [
                    ActionButton {
                        iconSource: Qt.resolvedUrl("assets/suspend.svgz")
                        text: i18ndc("plasma_lookandfeel_org.kde.lookandfeel","Suspend to RAM","Sleep")                        
                        onClicked: sddm.suspend()
                        enabled: sddm.canSuspend
                        visible: !inputPanel.keyboardActive
                    },
                    ActionButton {
                        iconSource: Qt.resolvedUrl("assets/restart.svgz")
                        text: i18nd("plasma_lookandfeel_org.kde.lookandfeel","Restart")
                        onClicked: sddm.reboot()
                        enabled: sddm.canReboot
                        visible: !inputPanel.keyboardActive
                    },
                    ActionButton {
                        iconSource: Qt.resolvedUrl("assets/shutdown.svgz")
                        text: i18nd("plasma_lookandfeel_org.kde.lookandfeel","Shut Down")
                        onClicked: sddm.powerOff()
                        enabled: sddm.canPowerOff
                        visible: !inputPanel.keyboardActive
                    },
                    ActionButton {
                        iconSource: Qt.resolvedUrl("assets/change_user.svgz")
                        text: i18nd("plasma_lookandfeel_org.kde.lookandfeel","Different User")
                        onClicked: mainStack.push(userPromptComponent)
                        enabled: true
                        visible: !userListComponent.showUsernamePrompt && !inputPanel.keyboardActive
                    }]

                onLoginRequest: {
                    root.notificationMessage = ""
                    sddm.login(username, password, sessionButton.currentIndex)
                }
            }

            Behavior on opacity {
                OpacityAnimator {
                    duration: units.longDuration
                }
            }
        }

        // Imported from org.kde.breeze.components
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

                // using a model rather than a QObject list to avoid QTBUG-75900
                userListModel: ListModel {
                    ListElement {
                        name: ""
                        iconSource: ""
                    }
                    Component.onCompleted: {
                        // as we can't bind inside ListElement
                        setProperty(0, "name", i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Type in Username and Password"));
                    }
                }

                onLoginRequest: {
                    root.notificationMessage = ""
                    sddm.login(username, password, sessionButton.currentIndex)
                }

                actionItems: [
                    ActionButton {
                        iconSource: Qt.resolvedUrl("assets/suspend.svgz")
                        text: i18ndc("plasma_lookandfeel_org.kde.lookandfeel","Suspend to RAM","Sleep")                        
                        onClicked: sddm.suspend()
                        enabled: sddm.canSuspend
                        visible: !inputPanel.keyboardActive
                    },
                    ActionButton {
                        iconSource: Qt.resolvedUrl("assets/restart.svgz")
                        text: i18nd("plasma_lookandfeel_org.kde.lookandfeel","Restart")
                        onClicked: sddm.reboot()
                        enabled: sddm.canReboot
                        visible: !inputPanel.keyboardActive
                    },
                    ActionButton {
                        iconSource: Qt.resolvedUrl("assets/shutdown.svgz")
                        text: i18nd("plasma_lookandfeel_org.kde.lookandfeel","Shut Down")
                        onClicked: sddm.powerOff()
                        enabled: sddm.canPowerOff
                        visible: !inputPanel.keyboardActive
                    },
                    ActionButton {
                        iconSource: "go-previous"
                        text: i18nd("plasma_lookandfeel_org.kde.lookandfeel","List Users")
                        onClicked: mainStack.pop()
                        visible: !inputPanel.keyboardActive
                    }
                ]
            }
        }

        Rectangle {
            id: formBg
            anchors.fill: mainStack
            anchors.centerIn: mainStack
            color: "#161925"
            opacity: 0.5
            z:-1
        }

        ShaderEffectSource {
            id: blurArea
            sourceItem: wallpaper
            width: formBg.width
            height: formBg.height
            anchors.centerIn: formBg
            sourceRect: Qt.rect(x,y,width,height)
            visible: true
            z:-2
        }

        GaussianBlur {
            id: blur
            height: formBg.height
            width: formBg.width
            source: blurArea
            radius: 50
            samples: 50 * 2 + 1
            cached: true
            anchors.centerIn: formBg
            visible: true
            z:-2
        }

        //Footer
        RowLayout {
            id: footer
            anchors {
                bottom: parent.bottom
                left: parent.left
                margins: units.smallSpacing
            }

            Behavior on opacity {
                OpacityAnimator {
                    duration: units.longDuration
                }
            }

            PlasmaComponents.ToolButton {
                text: i18ndc("plasma_lookandfeel_org.kde.lookandfeel", "Button to show/hide virtual keyboard", "Virtual Keyboard")
                font.pointSize: config.fontSize
                icon.name: inputPanel.keyboardActive ? "input-keyboard-virtual-on" : "input-keyboard-virtual-off"
                onClicked: {
                    // Otherwise the password field loses focus and virtual keyboard
                    // keystrokes get eaten
                    userListComponent.mainPasswordBox.forceActiveFocus();
                    inputPanel.showHide()
                }
                visible: inputPanel.status == Loader.Ready
            }

            KeyboardButton {
            }

            // Hidden per HasH design — no "Desktop Session: Plasma (Wayland)" label.
            // Kept (not deleted) so sddm.login() still has a valid currentIndex
            // (the default/last session is used).
            SessionButton {
                id: sessionButton
                visible: false
            }
        }
    }

    Connections {
        target: sddm
        onLoginFailed: {
            notificationMessage = i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Login Failed")
        }
        onLoginSucceeded: {
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
