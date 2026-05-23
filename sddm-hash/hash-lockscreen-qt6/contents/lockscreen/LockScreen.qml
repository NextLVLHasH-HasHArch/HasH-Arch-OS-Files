/*
    SPDX-FileCopyrightText: 2014 Aleix Pol Gonzalez <aleixpol@blue-systems.com>

    SPDX-License-Identifier: GPL-2.0-or-later

    HasH Sweet lock screen - Qt6 / Plasma 6 port.
    Root item that kscreenlocker loads. Mirrors the stock Plasma 6
    org.kde.plasma.desktop LockScreen.qml so Plasma accepts the QML
    (the old Qt5 version was rejected as "Lockscreen QML outdated").
*/

import QtQuick

Item {
    id: root
    property bool debug: false
    property string notification
    signal clearPassword()
    signal notificationRepeated()

    // These are magical properties that kscreenlocker looks for
    property bool viewVisible: false
    property bool suspendToRamSupported: false
    property bool suspendToDiskSupported: false

    // These are magical signals that kscreenlocker looks for
    signal suspendToDisk()
    signal suspendToRam()

    LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    implicitWidth: 800
    implicitHeight: 600

    LockScreenUi {
        anchors.fill: parent
    }
}
