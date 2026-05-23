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

import QtQuick 2.8
import QtQuick.Layouts 1.2
import QtQuick.Controls 2.4
import QtQuick.Controls.Styles 1.4

import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 2.0 as PlasmaComponents

import "../components"

SessionManagementScreen {

    property Item mainPasswordBox: passwordBox
    property bool lockScreenUiVisible: false

    // HasH 2FA: true once the lock greeter relays the verification-code prompt
    property bool twoFactorActive: false

    //the y position that should be ensured visible when the on screen keyboard is visible
    property int visibleBoundary: mapFromItem(loginButton, 0, 0).y
    onHeightChanged: visibleBoundary = mapFromItem(loginButton, 0, 0).y + loginButton.height + units.smallSpacing
    /*
     * Login has been requested with the following username and password
     * If username field is visible, it will be taken from that, otherwise from the "name" property of the currentIndex
     */
    signal loginRequest(string password)
    // HasH 2FA: the verification code was submitted (Enter or auto-submit at 6 digits)
    signal respondCode(string code)

    function startLogin() {
        var password = passwordBox.text

        //this is partly because it looks nicer
        //but more importantly it works round a Qt bug that can trigger if the app is closed with a TextField focused
        //See https://bugreports.qt.io/browse/QTBUG-55460
        loginButton.forceActiveFocus();
        loginRequest(password);
    }

    // HasH 2FA: slide the password field out (left) and the code field in (right)
    function activate2FA() {
        twoFactorActive = true
        codeBox.text = ""
        codeBox.forceActiveFocus()
    }
    function reset2FA() {
        twoFactorActive = false
        codeBox.text = ""
        passwordBox.selectAll()
        passwordBox.forceActiveFocus()
    }

    // expose the code field so the greeter can clear/refocus it if needed
    property Item verificationCodeBox: codeBox

    RowLayout {
        Layout.fillWidth: true

        // HasH 2FA: password and verification-code fields share one slot and slide.
        Item {
            id: credSlot
            Layout.fillWidth: true
            implicitHeight: passwordBox.implicitHeight
            clip: true

            TextField {
                id: passwordBox
                width: parent.width
                font.pointSize: theme.defaultFont.pointSize + 1
                placeholderText: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Password")
                focus: true
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                enabled: !authenticator.graceLocked && !twoFactorActive

                placeholderTextColor: "#C3C7D1"
                palette.text: "#C3C7D1"

                // slide out to the left when 2FA takes over
                x: twoFactorActive ? -width : 0
                opacity: twoFactorActive ? 0.0 : 1.0
                Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 180 } }

                background: Rectangle {
                    color: "#161925"
                    border.width: 1
                    border.color: "#0C0E15"
                    opacity: 0.7
                    radius: parent.width / 2
                    height: 35
                    width: passwordBox.width + 20
                    anchors.centerIn: parent
                }

                onAccepted: {
                    if (lockScreenUiVisible) {
                        startLogin();
                    }
                }

                //if empty and left or right is pressed change selection in user switch
                //this cannot be in keys.onLeftPressed as then it doesn't reach the password box
                Keys.onPressed: {
                    if (event.key == Qt.Key_Left && !text) {
                        userList.decrementCurrentIndex();
                        event.accepted = true
                    }
                    if (event.key == Qt.Key_Right && !text) {
                        userList.incrementCurrentIndex();
                        event.accepted = true
                    }
                }

                Connections {
                    target: root
                    onClearPassword: {
                        passwordBox.forceActiveFocus()
                        passwordBox.selectAll()
                    }
                }
            }

            // verification-code field — identical lock-screen styling, slides in
            // from the right and auto-submits once the full code is entered.
            TextField {
                id: codeBox
                width: parent.width
                font.pointSize: theme.defaultFont.pointSize + 1
                placeholderText: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Verification code")
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhHiddenText | Qt.ImhSensitiveData
                enabled: twoFactorActive
                property int codeLen: 6

                placeholderTextColor: "#C3C7D1"
                palette.text: "#C3C7D1"

                x: twoFactorActive ? 0 : width
                opacity: twoFactorActive ? 1.0 : 0.0
                Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 180 } }

                background: Rectangle {
                    color: "#161925"
                    border.width: 1
                    border.color: "#0C0E15"
                    opacity: 0.7
                    radius: parent.width / 2
                    height: 35
                    width: codeBox.width + 20
                    anchors.centerIn: parent
                }

                onAccepted: if (text.length) respondCode(text)
                onTextChanged: if (text.length >= codeLen) respondCode(text)   // auto-submit
            }
        }

        Button {
            id: loginButton
            Accessible.name: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Unlock")
            implicitHeight: passwordBox.height - units.smallSpacing * 0.5 // otherwise it comes out taller than the password field
            text: ">"
            Layout.leftMargin: 30

            contentItem: Text {
                text: loginButton.text
                font: loginButton.font
                opacity: enabled ? 1.0 : 0.3
                color: "#ffffff"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }

            background: Rectangle {
                id: buttonBorder
                width: 30
                height: 40
                radius: width / 2
                rotation: -90
                anchors.centerIn: parent

                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#D300DC" }
                    GradientStop { position: 1.0; color: "#8700FF" }
                }
            }

            Rectangle {
                id: buttonBackground
                height: 28
                width: 38
                radius: height / 2
                anchors.centerIn: buttonBorder
                color: "#161925"
            }

            onClicked: twoFactorActive ? respondCode(codeBox.text) : startLogin()
        }
    }
}
