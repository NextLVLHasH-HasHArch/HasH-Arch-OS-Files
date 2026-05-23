// Standalone test of the HasH 2FA verification-code popup.
// Run: qml6 popuptest.qml  — verifies the popup renders + the response flow
// before any of it goes into the SDDM theme. In the real theme the popup is
// triggered by `sddm.promptRequested(msg, secret)` and OK calls
// `sddm.respondToPrompt(code)`; here a local property stands in for that.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: win
    visible: true
    width: 900; height: 560
    title: "HasH 2FA popup test"
    property string lastResponse: ""

    // a stand-in login background so we can see the popup over it
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0b1020" }
            GradientStop { position: 1.0; color: "#16223a" }
        }
    }
    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top; anchors.topMargin: 40
        text: "HasH-Arch login"; color: "white"; font.pixelSize: 26; font.bold: true
    }
    Button {
        anchors.centerIn: parent
        text: "Simulate PAM prompt"
        onClicked: { codePopup.message = "Verification code:"; codePopup.secret = true; codePopup.open() }
    }
    Label {
        anchors.bottom: parent.bottom; anchors.bottomMargin: 24
        anchors.horizontalCenter: parent.horizontalCenter
        color: win.lastResponse ? "#56c5d8" : "#8aa"
        text: win.lastResponse ? ("respondToPrompt(\"" + win.lastResponse + "\")") : "waiting for code…"
        font.pixelSize: 15
    }

    // ===== the reusable popup (this block drops into Sweet-Qt6 Login.qml) =====
    Popup {
        id: codePopup
        property string message: ""
        property bool secret: true
        signal responded(string answer)
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        modal: true; focus: true
        width: 260; implicitHeight: 52; padding: 0
        closePolicy: Popup.CloseOnEscape
        background: Item {}                       // no box, no border — just the field
        // fancy slide-in (stands in for the login/lock screen sliding to the code field)
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 180 }
            NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: 220; easing.type: Easing.OutCubic }
        }
        onOpened: codeField.forceActiveFocus()
        property int codeLen: 6
        TextField {
            id: codeField
            anchors.fill: parent
            echoMode: codePopup.secret ? TextInput.Password : TextInput.Normal
            inputMethodHints: Qt.ImhDigitsOnly
            horizontalAlignment: TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter
            font.pixelSize: 24; font.letterSpacing: 8; color: "white"
            placeholderText: codePopup.message          // the prompt IS the only label
            placeholderTextColor: "#7c8a8d"
            onAccepted: { codePopup.responded(text); codePopup.close() }
            // auto-submit + close once the full code is entered
            onTextChanged: if (text.length >= codePopup.codeLen) { codePopup.responded(text); codePopup.close() }
            background: Item {                           // only a thin focus underline, no border
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width * 0.62; height: 2; radius: 1
                    color: codeField.activeFocus ? "#56c5d8" : Qt.rgba(1, 1, 1, 0.18)
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }
        }
        onResponded: (ans) => { win.lastResponse = ans }   // in SDDM: sddm.respondToPrompt(ans)
    }

    // auto-open once so the test screenshot captures the popup
    Component.onCompleted: { codePopup.message = "Verification code:"; codePopup.secret = true; codePopup.open() }
}
