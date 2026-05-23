// HasH SDDM theme — rounded text field matching the HasH Breeze lock screen.
// Fill #161925, border #0C0E15 (focus #8700FF), text #C3C7D1.
// Used by the username, password AND 2FA verification-code fields so all three
// share the lock-screen look. Built on QtQuick.Controls 2 TextField so it keeps
// full Controls2 behaviour (selection, IME, accessibility).
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

QQC2.TextField {
    id: control

    color: "#C3C7D1"
    placeholderTextColor: Qt.rgba(0.765, 0.78, 0.82, 0.6) // #C3C7D1 @ 60%
    palette.text: "#C3C7D1"
    palette.highlight: "#8700FF"
    palette.highlightedText: "#ffffff"

    selectByMouse: true
    leftPadding: Kirigami.Units.gridUnit
    rightPadding: Kirigami.Units.gridUnit
    topPadding: Kirigami.Units.smallSpacing + 2
    bottomPadding: Kirigami.Units.smallSpacing + 2

    background: Rectangle {
        radius: Kirigami.Units.smallSpacing + 2
        color: "#161925"
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? "#8700FF" : "#0C0E15"

        Behavior on border.color {
            ColorAnimation { duration: Kirigami.Units.shortDuration }
        }
    }
}
