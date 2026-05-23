/*
    SPDX-FileCopyrightText: 2014 Aleix Pol Gonzalez <aleixpol@blue-systems.com>

    SPDX-License-Identifier: GPL-2.0-or-later

    HasH Sweet lock screen - Qt6 / Plasma 6 port.

    This is a port of the stock Plasma 6 org.kde.plasma.desktop LockScreenUi.qml,
    restyled to the HasH "Sweet" look and extended with the HasH 2FA
    password->code slide. All imports and the authenticator wiring match the
    stock (known-good) lock screen, which is why Plasma 6 accepts this QML and no
    longer logs "Lockscreen QML outdated, falling back to default".

    Qt5 -> Qt6 changes vs the old Sweet lock:
      QtQuick 2.8                       -> QtQuick
      QtQuick.Controls 1.1 (+Styles 1.4)-> QtQuick.Controls (Controls 2, rewritten widgets)
      QtGraphicalEffects 1.0            -> Qt5Compat.GraphicalEffects
      org.kde.plasma.core 2.0           -> org.kde.plasma.core as PlasmaCore (+ kirigami for theming)
      org.kde.plasma.components 2.0     -> org.kde.plasma.components as PlasmaComponents3
      org.kde.plasma.private.sessions 2.0 -> org.kde.plasma.private.sessions (unversioned)
      PlasmaCore.DataSource keystate    -> org.kde.plasma.private.keyboardindicator KeyState
      PlasmaCore.ColorScope/colorGroup  -> Kirigami.Theme.colorSet = Complementary
      tryUnlock / Qt5 auth              -> authenticator.startAuthenticating()/respond()
*/

import QtQml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.workspace.components as PW
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator
import org.kde.kirigami as Kirigami

import org.kde.plasma.private.sessions
import org.kde.breeze.components

Item {
    id: lockScreenUi

    // If we're using software rendering, draw outlines instead of shadows
    readonly property bool softwareRendering: GraphicsInfo.api === GraphicsInfo.Software

    // HasH 2FA: set once the password (first secret) was responded-to, so that a
    // following promptForSecret is treated as the verification-code prompt.
    property bool passwordSubmitted: false

    // HasH 2FA: true if the secret prompt text looks like a TOTP/2FA request
    // rather than the initial password prompt.
    function isCodePrompt(text) {
        if (!text) {
            return false;
        }
        const t = ("" + text).toLowerCase();
        return t.indexOf("code") !== -1
            || t.indexOf("verification") !== -1
            || t.indexOf("otp") !== -1
            || t.indexOf("token") !== -1
            || t.indexOf("authenticator") !== -1;
    }

    function handleMessage(msg) {
        if (!root.notification) {
            root.notification += msg;
        } else if (root.notification.includes(msg)) {
            root.notificationRepeated();
        } else {
            root.notification += "\n" + msg
        }
    }

    // HasH dark palette: complementary (light text on dark) like the stock lock.
    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Complementary

    Connections {
        target: authenticator

        function onFailed(kind) {
            if (kind != 0) { // non-interactive authenticators (e.g. fingerprint)
                return;
            }
            const msg = i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Unlocking failed");
            lockScreenUi.handleMessage(msg);
            // HasH 2FA: a failure resets back to the password field
            lockScreenUi.passwordSubmitted = false;
            mainBlock.reset2FA();
            graceLockTimer.restart();
            notificationRemoveTimer.restart();
            rejectPasswordAnimation.start();
        }

        function onSucceeded() {
            if (authenticator.hadPrompt) {
                Qt.quit();
            } else {
                mainStack.replace(null, Qt.resolvedUrl("NoPasswordUnlock.qml"),
                    {
                        userListModel: users
                    },
                    StackView.Immediate,
                );
                mainStack.forceActiveFocus();
            }
        }

        function onInfoMessageChanged() {
            lockScreenUi.handleMessage(authenticator.infoMessage);
        }

        function onErrorMessageChanged() {
            lockScreenUi.handleMessage(authenticator.errorMessage);
        }

        function onPromptChanged(msg) {
            lockScreenUi.handleMessage(authenticator.prompt);
        }

        // Secret prompt. PAM (with pam_google_authenticator) fires this for the
        // FIRST secret (password) and then AGAIN for the SECOND secret (code).
        // We distinguish them two ways: passwordSubmitted (password already
        // responded-to) and/or the prompt text looking like a code request.
        // Password-only users only ever get the first prompt -> code field never
        // appears, so they are unaffected.
        function onPromptForSecretChanged(msg) {
            // NB: the signal arg is undefined — the text is in authenticator.promptForSecret.
            // Detect the 2FA code prompt by its TEXT (robust across all monitors),
            // not just the per-screen passwordSubmitted flag.
            if (lockScreenUi.isCodePrompt(authenticator.promptForSecret) || lockScreenUi.passwordSubmitted) {
                mainBlock.activate2FA();
            } else {
                mainBlock.mainPasswordBox.forceActiveFocus();
            }
        }
    }

    SessionManagement {
        id: sessionManagement
    }

    SessionsModel {
        id: sessionsModel
        showNewSessionEntry: false
    }

    KeyboardIndicator.KeyState {
        id: capsLockState
        key: Qt.Key_CapsLock
    }

    Connections {
        target: sessionManagement
        function onAboutToSuspend() {
            root.clearPassword();
        }
    }

    RejectPasswordAnimation {
        id: rejectPasswordAnimation
        target: mainBlock
    }

    MouseArea {
        id: lockScreenRoot

        property bool uiVisible: false
        property bool seenPositionChange: false
        property bool blockUI: containsMouse && (mainStack.depth > 1 || mainBlock.mainPasswordBox.text.length > 0 || inputPanel.keyboardActive)

        x: parent.x
        y: parent.y
        width: parent.width
        height: parent.height
        hoverEnabled: true
        cursorShape: uiVisible ? Qt.ArrowCursor : Qt.BlankCursor
        drag.filterChildren: true
        onPressed: uiVisible = true;
        onPositionChanged: {
            uiVisible = seenPositionChange;
            seenPositionChange = true;
        }
        onUiVisibleChanged: {
            if (uiVisible) {
                Window.window.requestActivate();
            }

            if (blockUI) {
                fadeoutTimer.running = false;
            } else if (uiVisible) {
                fadeoutTimer.restart();
            }
            authenticator.startAuthenticating();
        }
        onBlockUIChanged: {
            if (blockUI) {
                fadeoutTimer.running = false;
                uiVisible = true;
            } else {
                fadeoutTimer.restart();
            }
        }
        onExited: {
            uiVisible = false;
        }
        Keys.onEscapePressed: {
            if (uiVisible) {
                uiVisible = false;
                if (inputPanel.keyboardActive) {
                    inputPanel.showHide();
                }
                root.clearPassword();
            }
        }
        Keys.onPressed: event => {
            uiVisible = true;
            event.accepted = false;
        }
        Timer {
            id: fadeoutTimer
            interval: 10000
            onTriggered: {
                if (!lockScreenRoot.blockUI) {
                    lockScreenRoot.uiVisible = false;
                }
            }
        }
        Timer {
            id: notificationRemoveTimer
            interval: 3000
            onTriggered: root.notification = ""
        }
        Timer {
            id: graceLockTimer
            interval: 3000
            onTriggered: {
                root.clearPassword();
                authenticator.startAuthenticating();
            }
        }

        PropertyAnimation {
            id: launchAnimation
            target: lockScreenRoot
            property: "opacity"
            from: 0
            to: 1
            duration: Kirigami.Units.veryLongDuration * 2
        }

        Component.onCompleted: launchAnimation.start();

        // Wallpaper dim/blur. `wallpaper` is the kscreenlocker-provided context
        // item; the matrixrain WeatherScene wallpaper plugin (set via
        // kscreenlockerrc WallpaperPlugin=com.hash.matrixrain) feeds it, so we
        // must NOT replace it here - just fade/blur it like the stock lock does.
        WallpaperFader {
            anchors.fill: parent
            state: lockScreenRoot.uiVisible ? "on" : "off"
            source: wallpaper
            mainStack: mainStack
            footer: footer
            clock: clock
            alwaysShowClock: config.alwaysShowClock && !config.hideClockWhenIdle
        }

        DropShadow {
            id: clockShadow
            anchors.fill: clock
            source: clock
            visible: false   // HasH: KDE clock hidden — the matrixrain wallpaper draws the desktop time/date/location/temp block
            radius: 7
            verticalOffset: 0.8
            samples: 15
            spread: 0.2
            color: Qt.rgba(0, 0, 0, 0.7)
            opacity: lockScreenRoot.uiVisible ? 0 : 1
            Behavior on opacity {
                OpacityAnimator {
                    duration: Kirigami.Units.veryLongDuration * 2
                    easing.type: Easing.InOutQuad
                }
            }
        }

        Clock {
            id: clock
            property Item shadow: clockShadow
            visible: false   // HasH: hidden; matrixrain wallpaper provides the clock/date/temp block
            anchors.horizontalCenter: parent.horizontalCenter
            y: (mainBlock.userList.y + mainStack.y) / 2 - height / 2
            Layout.alignment: Qt.AlignBaseline
        }

        ListModel {
            id: users

            Component.onCompleted: {
                users.append({
                    name: kscreenlocker_userName,
                    realName: kscreenlocker_userName,
                    icon: kscreenlocker_userImage !== ""
                          ? "file://" + kscreenlocker_userImage.split("/").map(encodeURIComponent).join("/")
                          : "",
                })
            }
        }

        // HasH dark translucent panel behind the unlock prompt (#161925),
        // matching the Sweet look. Sits behind the StackView.
        Rectangle {
            id: formBg
            anchors.fill: mainStack
            color: "#161925"
            opacity: 0.45
            radius: Kirigami.Units.gridUnit * 0.5
            visible: mainStack.opacity > 0
            z: -1
        }

        StackView {
            id: mainStack
            anchors {
                left: parent.left
                right: parent.right
            }
            height: lockScreenRoot.height + Kirigami.Units.gridUnit * 3
            focus: true //StackView is an implicit focus scope

            visible: opacity > 0

            initialItem: MainBlock {
                id: mainBlock
                lockScreenUiVisible: lockScreenRoot.uiVisible

                showUserList: userList.y + mainStack.y > 0

                enabled: !graceLockTimer.running

                StackView.onStatusChanged: {
                    if (StackView.status === StackView.Activating) {
                        mainPasswordBox.clear();
                        mainPasswordBox.focus = true;
                        root.notification = "";
                        // HasH 2FA: a fresh presentation always starts on the password
                        lockScreenUi.passwordSubmitted = false;
                        reset2FA();
                    }
                }
                userListModel: users

                notificationMessage: {
                    const parts = [];
                    if (capsLockState.locked) {
                        parts.push(i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Caps Lock is on"));
                    }
                    if (root.notification) {
                        parts.push(root.notification);
                    }
                    return parts.join(" • ");
                }

                // Modern API: answer the password (first secret) prompt.
                onPasswordResult: password => {
                    lockScreenUi.passwordSubmitted = true; // HasH 2FA: next secret is the code
                    authenticator.respond(password);
                }

                // HasH 2FA: answer the verification-code (second secret) prompt.
                onCodeResult: code => {
                    authenticator.respond(code);
                }

                actionItems: [
                    ActionButton {
                        text: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Switch User")
                        icon.name: "system-switch-user"
                        onClicked: {
                            // If there are no existing sessions to switch to, create a new one instead
                            if (((sessionsModel.showNewSessionEntry && sessionsModel.count === 1) ||
                               (!sessionsModel.showNewSessionEntry && sessionsModel.count === 0)) &&
                               sessionsModel.canSwitchUser) {
                                mainStack.pop({immediate: true})
                                sessionsModel.startNewSession(true /* lock the screen too */)
                                lockScreenRoot.state = ''
                            } else {
                                mainStack.push(switchSessionPage)
                            }
                        }
                        visible: sessionsModel.canStartNewSession && sessionsModel.canSwitchUser
                    }
                ]

                Loader {
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    Layout.fillWidth: true
                    Layout.preferredHeight: item ? item.implicitHeight : 0
                    active: config.showMediaControls
                    source: "MediaControls.qml"
                }
            }

            Component.onCompleted: {
                if (defaultToSwitchUser) { //context property
                    if (((sessionsModel.showNewSessionEntry && sessionsModel.count === 1) ||
                       (!sessionsModel.showNewSessionEntry && sessionsModel.count === 0)) &&
                       sessionsModel.canStartNewSession) {
                        sessionsModel.startNewSession(true /* lock the screen too */)
                    } else {
                        mainStack.push(switchSessionPage, { immediate: true });
                    }
                }
            }
        }

        Component {
            id: switchSessionPage
            SessionManagementScreen {
                property var switchSession: finalSwitchSession

                StackView.onStatusChanged: {
                    if (StackView.status === StackView.Activating) {
                        focus = true
                    }
                }

                userListModel: sessionsModel

                function initSwitchSession() {
                    lockScreenRoot.state = 'onOtherSession'
                }

                function finalSwitchSession() {
                    mainStack.pop({immediate: true})
                    sessionsModel.switchUser(userListCurrentItem.model.vtNumber)
                    lockScreenRoot.state = ''
                }

                Keys.onLeftPressed: userList.decrementCurrentIndex()
                Keys.onRightPressed: userList.incrementCurrentIndex()
                Keys.onEnterPressed: initSwitchSession()
                Keys.onReturnPressed: initSwitchSession()
                Keys.onEscapePressed: mainStack.pop()

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing

                    PlasmaComponents3.Button {
                        Layout.fillWidth: true
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                        text: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Switch to This Session")
                        onClicked: initSwitchSession()
                        visible: sessionsModel.count > 0
                    }

                    PlasmaComponents3.Button {
                        Layout.fillWidth: true
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                        text: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Start New Session")
                        onClicked: {
                            mainStack.pop({immediate: true})
                            sessionsModel.startNewSession(true /* lock the screen too */)
                            lockScreenRoot.state = ''
                        }
                    }
                }

                actionItems: [
                    ActionButton {
                        icon.name: "go-previous"
                        text: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Back")
                        onClicked: mainStack.pop()
                    }
                ]
            }
        }

        VirtualKeyboardLoader {
            id: inputPanel

            z: 1

            screenRoot: lockScreenRoot
            mainStack: mainStack
            mainBlock: mainBlock
            passwordField: mainBlock.mainPasswordBox
        }

        Loader {
            z: 2
            active: root.viewVisible
            source: "LockOsd.qml"
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: Kirigami.Units.gridUnit
            }
        }

        RowLayout {
            id: footer
            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
                margins: Kirigami.Units.smallSpacing
            }
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.ToolButton {
                id: virtualKeyboardButton

                focusPolicy: Qt.TabFocus
                text: i18ndc("plasma_lookandfeel_org.kde.lookandfeel", "Button to show/hide virtual keyboard", "Virtual Keyboard")
                icon.name: inputPanel.keyboardActive ? "input-keyboard-virtual-on" : "input-keyboard-virtual-off"
                onClicked: {
                    mainBlock.mainPasswordBox.forceActiveFocus();
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

            PlasmaComponents3.ToolButton {
                id: keyboardButton

                focusPolicy: Qt.TabFocus
                Accessible.description: i18ndc("plasma_lookandfeel_org.kde.lookandfeel", "Button to change keyboard layout", "Switch layout")
                icon.name: "input-keyboard"

                PW.KeyboardLayoutSwitcher {
                    id: keyboardLayoutSwitcher

                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                }

                text: keyboardLayoutSwitcher.layoutNames.longName
                onClicked: keyboardLayoutSwitcher.keyboardLayout.switchToNextLayout()

                visible: keyboardLayoutSwitcher.hasMultipleKeyboardLayouts

                Layout.fillHeight: true
                containmentMask: Item {
                    parent: keyboardButton
                    anchors.fill: parent
                    anchors.leftMargin: virtualKeyboardButton.visible ? 0 : -footer.anchors.margins
                    anchors.bottomMargin: -footer.anchors.margins
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Battery {}
        }

        states: [
            State {
                name: "onOtherSession"
                // for slide out animation
                PropertyChanges { lockScreenRoot.y: lockScreenRoot.height }
                PropertyChanges { lockScreenRoot.opacity: 0 }
            }
        ]

        transitions: Transition {
            from: ""
            to: "onOtherSession"

            PropertyAnimation { properties: "y"; duration: 300; easing.type: Easing.InQuad }
            PropertyAnimation { properties: "opacity"; duration: 300 }

            onRunningChanged: {
                if (!running) {
                    mainStack.currentItem.switchSession()
                }
            }
        }
    }
}
