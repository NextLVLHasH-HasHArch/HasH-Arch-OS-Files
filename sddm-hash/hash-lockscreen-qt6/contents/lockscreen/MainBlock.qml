/*
    SPDX-FileCopyrightText: 2016 David Edmundson <davidedmundson@kde.org>

    SPDX-License-Identifier: LGPL-2.0-or-later

    HasH Sweet lock screen MainBlock - Qt6 / Plasma 6.

    Built on the stock breeze SessionManagementScreen (known-good Qt6), but
    restyled to the HasH look:
      - #161925 rounded password / code field with #0C0E15 border, #C3C7D1 text
        (from the Sweet-Qt6 SDDM Input.qml)
      - magenta -> violet (#D300DC -> #8700FF) unlock button
    Adds the HasH 2FA password->code SLIDE: the password field slides left/out
    and a "Verification code" field slides in from the right, auto-submitting at
    6 digits. Mirrors the Sweet-Qt6 SDDM Login.qml credentialSlider, but wired to
    the modern lock-screen authenticator API (respond()), not sddm.respondToPrompt().

    Auth wiring is identical in structure to the stock MainBlock:
      - signal passwordResult(password) -> authenticator.respond() in LockScreenUi
      - startLogin() forces focus off the field (QTBUG-55460) then emits the signal
    Password-only users never see the code field (twoFactorActive stays false).
*/

import QtQuick

import QtQuick.Layouts
import QtQuick.Controls as QQC2

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import org.kde.breeze.components

SessionManagementScreen {
    id: sessionManager

    readonly property alias mainPasswordBox: passwordBox
    property bool lockScreenUiVisible: false

    // HasH 2FA: true once the verification-code prompt is active (the password
    // was already responded to / a code prompt arrived). Drives the slide.
    property bool twoFactorActive: false
    // expose the code field so the greeter can clear/refocus it if needed
    readonly property alias verificationCodeBox: codeBox

    //the y position that should be ensured visible when the on screen keyboard is visible
    property int visibleBoundary: mapFromItem(loginButton, 0, 0).y
    onHeightChanged: visibleBoundary = mapFromItem(loginButton, 0, 0).y + loginButton.height + Kirigami.Units.smallSpacing

    /*
     * Login has been requested with the given password (first secret).
     * LockScreenUi connects this to authenticator.respond().
     */
    signal passwordResult(string password)
    // HasH 2FA: the verification code was submitted (Enter or auto-submit at 6 digits)
    signal codeResult(string code)

    onUserSelected: {
        const nextControl = (passwordBox.visible ? passwordBox : loginButton);
        nextControl.forceActiveFocus(Qt.TabFocusReason);
    }

    function startLogin() {
        const password = passwordBox.text
        // This works round QTBUG-55460 (closing the app with a TextField focused).
        loginButton.forceActiveFocus();
        passwordResult(password);
    }

    // HasH 2FA: slide the password field out (left), the code field in (right).
    function activate2FA() {
        twoFactorActive = true
        codeBox.text = ""
        codeBox.forceActiveFocus()
    }
    // HasH 2FA: slide back to the password field (e.g. after a failure).
    function reset2FA() {
        twoFactorActive = false
        codeBox.text = ""
        passwordBox.selectAll()
        passwordBox.forceActiveFocus()
    }

    RowLayout {
        Layout.fillWidth: true

        // HasH 2FA: password and verification-code fields share one slot and slide.
        Item {
            id: credSlot
            Layout.fillWidth: true
            implicitHeight: passwordBox.implicitHeight
            clip: true

            QQC2.TextField {
                id: passwordBox
                width: parent.width
                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                text: PasswordSync.password

                placeholderText: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Password")
                focus: true
                echoMode: TextInput.Password
                // Hard cap the field so no oversized/scripted payload can be
                // pasted/injected into the unlock input.
                maximumLength: 32
                inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                enabled: !authenticator.graceLocked && !sessionManager.twoFactorActive

                // HasH palette
                placeholderTextColor: "#C3C7D1"
                color: "#C3C7D1"

                cursorVisible: visible

                // HasH slide: off-screen (right) until the unlock UI appears, then
                // slides IN to centre; slides OUT to the left when 2FA takes over.
                x: !sessionManager.lockScreenUiVisible ? width
                   : (sessionManager.twoFactorActive ? -width : 0)
                opacity: (sessionManager.lockScreenUiVisible && !sessionManager.twoFactorActive) ? 1.0 : 0.0
                Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 180 } }

                // HasH #161925 rounded field (from Sweet-Qt6 Input.qml)
                background: Rectangle {
                    anchors.fill: parent
                    color: "#161925"
                    opacity: 0.7
                    radius: height / 2
                    border.width: 1
                    border.color: passwordBox.activeFocus ? "#8700FF" : "#0C0E15"
                }

                // HasH: no accept button + no Enter required. The password
                // auto-submits a moment after you stop typing (debounced); Enter
                // still works as a fallback. PAM then issues the 2FA prompt which
                // slides us to the code field (which auto-submits at 6 digits).
                onAccepted: sessionManager.startLogin()
                onTextChanged: {
                    if (text.length > 0 && !sessionManager.twoFactorActive)
                        autoSubmitTimer.restart();
                    else
                        autoSubmitTimer.stop();
                }

                // debounce: submit ~1s after the last keystroke (no Enter needed)
                Timer {
                    id: autoSubmitTimer
                    interval: 1000
                    // CRITICAL on multi-monitor: only the focused field (the one
                    // window the user is typing in) submits — otherwise every
                    // screen's instance fires respond() and races/locks the account.
                    onTriggered: {
                        if (passwordBox.activeFocus && passwordBox.text.length > 0
                                && !sessionManager.twoFactorActive
                                && !authenticator.graceLocked)
                            sessionManager.startLogin();
                    }
                }

                //if empty and left or right is pressed change selection in user switch
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Left && !text) {
                        sessionManager.userList.decrementCurrentIndex();
                        event.accepted = true
                    }
                    if (event.key === Qt.Key_Right && !text) {
                        sessionManager.userList.incrementCurrentIndex();
                        event.accepted = true
                    }
                }

                Connections {
                    target: root
                    function onClearPassword() {
                        passwordBox.forceActiveFocus()
                        passwordBox.text = "";
                        passwordBox.text = Qt.binding(() => PasswordSync.password);
                    }
                    function onNotificationRepeated() {
                        sessionManager.playHighlightAnimation();
                    }
                }
            }

            // verification-code field — identical HasH styling, slides in from
            // the right and auto-submits once the full code is entered.
            QQC2.TextField {
                id: codeBox
                width: parent.width
                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                placeholderText: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Verification code")
                echoMode: TextInput.Password
                maximumLength: 6   // a TOTP code is exactly 6 digits
                inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhHiddenText | Qt.ImhSensitiveData
                enabled: sessionManager.twoFactorActive
                property int codeLen: 6

                placeholderTextColor: "#C3C7D1"
                color: "#C3C7D1"

                x: sessionManager.twoFactorActive ? 0 : width
                opacity: sessionManager.twoFactorActive ? 1.0 : 0.0
                Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 180 } }

                background: Rectangle {
                    anchors.fill: parent
                    color: "#161925"
                    opacity: 0.7
                    radius: height / 2
                    border.width: 1
                    border.color: codeBox.activeFocus ? "#8700FF" : "#0C0E15"
                }

                onAccepted: if (text.length) sessionManager.codeResult(text)
                // auto-submit at full length, but only from the focused screen
                // (multi-monitor: avoid every instance firing respond()).
                onTextChanged: if (activeFocus && text.length >= codeLen) sessionManager.codeResult(text)
            }
        }

        Binding {
            target: PasswordSync
            property: "password"
            value: passwordBox.text
        }

        // HasH magenta -> violet unlock / verify button
        QQC2.Button {
            id: loginButton
            // HasH: no visible accept button — password submits on Enter and the
            // 2FA code auto-submits at 6 digits. Kept hidden/zero-width only so the
            // existing focus + visibleBoundary references stay valid.
            visible: false
            Accessible.name: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Unlock")
            Layout.preferredHeight: passwordBox.implicitHeight
            Layout.preferredWidth: 0
            Layout.leftMargin: 0

            contentItem: Text {
                text: LayoutMirroring.enabled ? "‹" : "›" // ‹ / ›
                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 4
                font.bold: true
                opacity: loginButton.enabled ? 1.0 : 0.3
                color: "#ffffff"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            background: Rectangle {
                radius: height / 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#D300DC" }
                    GradientStop { position: 1.0; color: "#8700FF" }
                }
            }

            onClicked: sessionManager.twoFactorActive ? sessionManager.codeResult(codeBox.text) : sessionManager.startLogin()
            Keys.onEnterPressed: clicked()
            Keys.onReturnPressed: clicked()
        }
    }
}
