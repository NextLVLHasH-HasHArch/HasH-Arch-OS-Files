/*
    HasH SDDM theme — Login form.
    Based on Breeze's Login.qml (org.kde.breeze.components SessionManagementScreen,
    Kirigami.Units, i18ndc, full keyboard/escape/left-right user-switch handling)
    and extended with the HasH 2FA password->code slide relayed by the forked
    sddm-greeter-qt6 (sddm.promptRequested / sddm.respondToPrompt). HasH-styled
    rounded fields (components/Input.qml) and a magenta->violet primary button.

    SPDX-FileCopyrightText: 2016 David Edmundson <davidedmundson@kde.org>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import org.kde.breeze.components

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "components"

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
    onHeightChanged: visibleBoundary = mapFromItem(loginButton, 0, 0).y + loginButton.height + Kirigami.Units.smallSpacing

    property real fontSize: Kirigami.Theme.defaultFont.pointSize

    signal loginRequest(string username, string password)

    onShowUsernamePromptChanged: {
        if (!showUsernamePrompt) {
            lastUserName = ""
        }
    }

    onUserSelected: {
        // Don't startLogin() here, because the signal is connected to the
        // Escape key as well, for which it wouldn't make sense to trigger
        // login.
        passwordBox.clear()
        focusFirstVisibleFormControl();
    }

    QQC2.StackView.onActivating: {
        // Controls are not visible yet.
        Qt.callLater(focusFirstVisibleFormControl);
    }

    function focusFirstVisibleFormControl() {
        const nextControl = (userNameInput.visible
            ? userNameInput
            : (passwordBox.visible
                ? passwordBox
                : loginButton));
        // Using TabFocusReason, so that the loginButton gets the visual highlight.
        nextControl.forceActiveFocus(Qt.TabFocusReason);
    }

    /*
     * Login has been requested with the following username and password
     * If username field is visible, it will be taken from that, otherwise from the "name" property of the currentIndex
     */
    function startLogin() {
        const username = showUsernamePrompt ? userNameInput.text : userList.selectedUser
        const password = passwordBox.text

        footer.enabled = false
        mainStack.enabled = false
        userListComponent.userList.opacity = 0.75

        // This is partly because it looks nicer, but more importantly it
        // works round a Qt bug that can trigger if the app is closed with a
        // TextField focused.
        //
        // See https://bugreports.qt.io/browse/QTBUG-55460
        loginButton.forceActiveFocus();
        loginRequest(username, password);
    }

    Input {
        id: userNameInput
        font.pointSize: fontSize + 1
        Layout.fillWidth: true

        text: lastUserName
        visible: showUsernamePrompt && !root.twoFactorActive
        focus: showUsernamePrompt && !lastUserName //if there's a username prompt it gets focus first, otherwise password does
        placeholderText: i18ndc("plasma-desktop-sddm-theme", "@info:placeholder in textfield", "Username")

        onAccepted: {
            if (root.loginScreenUiVisible) {
                passwordBox.forceActiveFocus()
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true

        // HasH 2FA: the password and the verification-code field share one slot
        // and slide horizontally. On the password prompt the password sits at
        // x=0; once the daemon relays the code prompt (twoFactorActive) the
        // password slides out to the left and the code field slides in from the
        // right, auto-submitting at 6 digits.
        Item {
            id: credentialSlider
            Layout.fillWidth: true
            implicitHeight: passwordBox.implicitHeight
            clip: true

            Input {
                id: passwordBox
                font.pointSize: fontSize + 1
                width: parent.width

                placeholderText: i18ndc("plasma-desktop-sddm-theme",  "@info:placeholder in textfield", "Password")
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

                visible: root.showUsernamePrompt || userList.currentItem.needsPassword

                Keys.onEscapePressed: {
                    mainStack.currentItem.forceActiveFocus();
                }

                //if empty and left or right is pressed change selection in user switch
                //this cannot be in keys.onLeftPressed as then it doesn't reach the password box
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Left && !text) {
                        userList.decrementCurrentIndex();
                        event.accepted = true
                    }
                    if (event.key === Qt.Key_Right && !text) {
                        userList.incrementCurrentIndex();
                        event.accepted = true
                    }
                }

                // HasH 2FA: both sddm handlers live here, nested inside the
                // (QQuickItem) password field. A top-level Connections cannot be
                // a child of SessionManagementScreen because its default property
                // `_children` only accepts QQuickItems.
                Connections {
                    target: sddm
                    function onLoginFailed() {
                        root.twoFactorActive = false   // a failure resets back to the password
                        passwordBox.selectAll()
                        passwordBox.forceActiveFocus()
                    }
                    // the forked greeter relayed an extra (non-password) PAM
                    // prompt -> slide to the verification code
                    function onPromptRequested(message, secret) {
                        codeBox.text = ""
                        root.twoFactorActive = true
                        codeBox.forceActiveFocus()
                    }
                }
            }

            // verification-code field — same Input styling, slides in from the
            // right, auto-submits once the full code is entered.
            Input {
                id: codeBox
                font.pointSize: fontSize + 1
                width: parent.width
                echoMode: TextInput.Password
                placeholderText: i18ndc("plasma-desktop-sddm-theme", "@info:placeholder in textfield", "Verification code")
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

        // HasH: NO visible accept button. The password submits on Enter
        // (passwordBox.onAccepted -> startLogin) and the 2FA code auto-submits at
        // 6 digits (codeBox.onTextChanged -> sddm.respondToPrompt), so there is
        // nothing to click. This zero-width, invisible Item is kept ONLY as the
        // `loginButton` focus/geometry anchor that the rest of the form still
        // references (focusFirstVisibleFormControl fallback, the QTBUG-55460
        // forceActiveFocus() in startLogin, and the visibleBoundary used to keep
        // the field above the virtual keyboard).
        Item {
            id: loginButton
            Accessible.name: i18ndc("plasma-desktop-sddm-theme", "@action:button Accessible name", "Log in")
            Layout.preferredHeight: passwordBox.implicitHeight
            Layout.preferredWidth: 0
            implicitHeight: passwordBox.implicitHeight
            visible: false

            // Still submit if focus somehow lands here and Enter is pressed, so
            // keyboard navigation never dead-ends.
            Keys.onEnterPressed: root.twoFactorActive ? sddm.respondToPrompt(codeBox.text) : startLogin()
            Keys.onReturnPressed: root.twoFactorActive ? sddm.respondToPrompt(codeBox.text) : startLogin()
        }
    }
}
