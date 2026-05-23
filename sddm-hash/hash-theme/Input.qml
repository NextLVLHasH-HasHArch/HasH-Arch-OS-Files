// HasH-Arch: Sweet-Qt6 Input restyled to match the Sweet lock screen's password
// field (contents/lockscreen/MainBlock.qml): #161925 fill, #0C0E15 border,
// #C3C7D1 text. Install over /usr/share/sddm/themes/Sweet-Qt6/components/Input.qml.
// Used by the username, password AND 2FA verification-code fields, so all three
// share the lock screen's look.
import QtQuick
import QtQuick.Controls

TextField {
    placeholderTextColor: "#C3C7D1"
    palette.text: "#C3C7D1"
    font.pointSize: config.fontSize
    font.family: config.font
    width: parent.width
    background: Rectangle {
        color: "#161925"
        opacity: 0.7
        radius: parent.width / 2
        width: parent.width
        height: width / 9
        border.width: 1
        // base matches the lock screen; keep a focus highlight for usability
        border.color: parent.focus ? config.selected_color : "#0C0E15"
        anchors.fill: parent
    }
}
