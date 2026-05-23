/*
    HasH Notifications — a system-tray notification COUNT badge + centre.
    KDE shows no numeric badge natively; this reads org.kde.notificationmanager
    and shows how many notifications you have, with a popup list.
*/
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import org.kde.notificationmanager as NotificationManager

PlasmoidItem {
    id: root

    // "how many you have": prefer unread (persisted), else currently-active.
    readonly property int cnt: notifModel.unreadNotificationsCount > 0
                               ? notifModel.unreadNotificationsCount
                               : notifModel.activeNotificationsCount

    NotificationManager.Notifications {
        id: notifModel
        showExpired: true
        showDismissed: true
        showJobs: false
        groupMode: NotificationManager.Notifications.GroupDisabled
    }

    Plasmoid.status: cnt > 0 ? PlasmaCore.Types.ActiveStatus
                             : PlasmaCore.Types.PassiveStatus
    toolTipMainText: i18n("Notifications")
    toolTipSubText: cnt > 0 ? i18np("%1 unread notification", "%1 unread notifications", cnt)
                            : i18n("No new notifications")

    preferredRepresentation: compactRepresentation

    compactRepresentation: MouseArea {
        id: compact
        property real iconSize: Math.min(width, height)
        onClicked: root.expanded = !root.expanded

        Kirigami.Icon {
            anchors.centerIn: parent
            width: compact.iconSize
            height: compact.iconSize
            source: "preferences-desktop-notification"
            active: compact.containsMouse
        }

        Rectangle {                       // the count badge
            visible: root.cnt > 0
            anchors { right: parent.right; top: parent.top }
            height: Math.round(compact.iconSize * 0.46)
            width: Math.max(height, badgeLbl.implicitWidth + height * 0.5)
            radius: height / 2
            color: "#56c5d8"
            border.color: "#0e1117"
            border.width: Math.max(1, Math.round(height * 0.08))
            PC3.Label {
                id: badgeLbl
                anchors.centerIn: parent
                text: root.cnt > 99 ? "99+" : root.cnt
                color: "#06222a"
                font.pixelSize: Math.round(parent.height * 0.64)
                font.bold: true
            }
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 19
        Layout.minimumHeight: Kirigami.Units.gridUnit * 22
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Heading {
            level: 3
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            text: root.cnt > 0 ? i18np("%1 notification", "%1 notifications", root.cnt)
                               : i18n("Notifications")
        }

        PC3.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: list
                model: notifModel
                clip: true
                spacing: Kirigami.Units.smallSpacing
                delegate: Kirigami.AbstractCard {
                    width: ListView.view ? ListView.view.width : implicitWidth
                    contentItem: ColumnLayout {
                        spacing: 2
                        PC3.Label {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.bold: true
                            text: (model.summary && model.summary.length > 0)
                                  ? model.summary
                                  : (model.applicationName || i18n("Notification"))
                        }
                        PC3.Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            opacity: 0.8
                            visible: text.length > 0
                            text: model.body || ""
                        }
                    }
                }
            }
        }

        PC3.Label {
            visible: list.count === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            opacity: 0.6
            text: i18n("No notifications")
        }
    }
}
