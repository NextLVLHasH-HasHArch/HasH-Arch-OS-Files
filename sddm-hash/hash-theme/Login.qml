// HasH-Arch: Sweet-Qt6 Login.qml patched for the 2FA verification-code field.
// Install over /usr/share/sddm/themes/Sweet-Qt6/Login.qml (back up the original first).
// The code field reuses the same `Input` component as the password (identical
// styling), slides in when the daemon relays a PAM prompt (sddm.promptRequested),
// and auto-submits the code via sddm.respondToPrompt().
import "components"

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

import org.kde.plasma.components as PlasmaComponents

SessionManagementScreen {
    id: root
    property Item mainPasswordBox: passwordBox

    property bool showUsernamePrompt: !showUserList

    property string lastUserName
    property bool loginScreenUiVisible: false

    // HasH 2FA: true once the daemon relays a verification-code prompt
    property bool twoFactorActive: false

    //the y position that should be ensured visible when the on screen keyboard is visible
    property int visibleBoundary: mapFromItem(loginButton, 0, 0).y
    onHeightChanged: visibleBoundary = mapFromItem(loginButton, 0, 0).y + loginButton.height + units.smallSpacing

    signal loginRequest(string username, string password)

    onShowUsernamePromptChanged: {
        if (!showUsernamePrompt) {
            lastUserName = ""
        }
    }

    function startLogin() {
        var username = showUsernamePrompt ? userNameInput.text : userList.selectedUser
        var password = passwordBox.text
        loginButton.forceActiveFocus();
        loginRequest(username, password);
    }

    Input {
        id: userNameInput
        Layout.fillWidth: true
        text: lastUserName
        visible: showUsernamePrompt && !root.twoFactorActive
        focus: showUsernamePrompt && !lastUserName
        Layout.topMargin: 10
        Layout.bottomMargin: 10
        placeholderText: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Username")

        onAccepted:
            if (root.loginScreenUiVisible) {
                passwordBox.forceActiveFocus()
            }
    }

    // HasH 2FA: the password and the verification-code field share one slot and
    // slide horizontally. On the password prompt the password field sits at x=0;
    // once the daemon relays the code prompt (twoFactorActive) the password slides
    // out to the left and the code field slides in from the right. Same behaviour
    // is mirrored on the Sweet lock screen (MainBlock.qml).
    Item {
        id: credentialSlider
        Layout.fillWidth: true
        Layout.topMargin: 10
        implicitHeight: passwordBox.implicitHeight
        clip: true

        Input {
            id: passwordBox
            width: parent.width
            placeholderText: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Password")
            focus: !showUsernamePrompt || lastUserName
            echoMode: TextInput.Password
            enabled: !root.twoFactorActive

            // slide out to the left when the code field takes over
            x: root.twoFactorActive ? -width : 0
            opacity: root.twoFactorActive ? 0.0 : 1.0
            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 180 } }

            onAccepted: {
                if (root.loginScreenUiVisible) {
                    startLogin();
                }
            }

            Keys.onEscapePressed: {
                mainStack.currentItem.forceActiveFocus();
            }

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

            // HasH 2FA: both sddm handlers live here, nested inside the (QQuickItem)
            // password field. A top-level Connections cannot be a child of
            // SessionManagementScreen because its default property `_children` only
            // accepts QQuickItems (this was the bug that broke the greeter).
            Connections {
                target: sddm
                function onLoginFailed() {
                    root.twoFactorActive = false       // a failure resets back to the password
                    passwordBox.selectAll()
                    passwordBox.forceActiveFocus()
                }
                // the daemon relayed an extra (non-password) PAM prompt -> slide to the code
                function onPromptRequested(message, secret) {
                    codeBox.text = ""
                    root.twoFactorActive = true
                    codeBox.forceActiveFocus()
                }
            }
        }

        // verification-code field — same Input styling, slides in from the right,
        // auto-submits once the full code is entered.
        Input {
            id: codeBox
            width: parent.width
            echoMode: TextInput.Password
            placeholderText: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Verification code")
            enabled: root.twoFactorActive
            property int codeLen: 6

            x: root.twoFactorActive ? 0 : width
            opacity: root.twoFactorActive ? 1.0 : 0.0
            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 180 } }

            onAccepted: if (text.length) sddm.respondToPrompt(text)
            onTextChanged: if (text.length >= codeLen) sddm.respondToPrompt(text)   // auto-submit
        }
    }

    PlasmaComponents.Button {
        id: loginButton
        text: root.twoFactorActive
              ? i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Verify")
              : i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Log In")
        enabled: root.twoFactorActive ? codeBox.text != "" : passwordBox.text != ""

        Layout.topMargin: 20
        Layout.fillWidth: true

        font.pointSize: config.fontSize
        font.family: config.font
        opacity: enabled ? 1.0 : 0.7

        contentItem: Text {
            text: loginButton.text
            font: loginButton.font
            color: "#ffffff"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        background: Rectangle {
            id: buttonBackground
            height: parent.width
            width: height / 9
            radius: width / 2
            rotation: -90
            anchors.centerIn: parent

            // matches the Sweet lock screen unlock button (MainBlock.qml)
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#D300DC" }
                GradientStop { position: 1.0; color: "#8700FF" }
            }
        }

        onClicked: root.twoFactorActive ? sddm.respondToPrompt(codeBox.text) : startLogin();
    }
}
