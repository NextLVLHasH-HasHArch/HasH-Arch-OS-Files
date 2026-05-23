/*
    SPDX-License-Identifier: GPL-2.0-or-later

    Qt6 lock-screen config KCM page. Mirrors the stock Plasma 6 lockscreen
    config.qml (Kirigami.FormLayout + KCM.SettingHighlighter).
*/

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

Kirigami.FormLayout {
    id: configForm

    property bool cfg_alwaysShowClock
    property bool cfg_hideClockWhenIdle
    property bool cfg_alwaysShowClockDefault: true
    property bool cfg_hideClockWhenIdleDefault: false

    property alias cfg_showMediaControls: showMediaControls.checked
    property bool cfg_showMediaControlsDefault: true

    twinFormLayouts: parentLayout

    QQC2.RadioButton {
        Kirigami.FormData.label: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Show clock:")
        text: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Always")
        checked: configForm.cfg_alwaysShowClock && !configForm.cfg_hideClockWhenIdle
        onToggled: {
            configForm.cfg_alwaysShowClock = true;
            configForm.cfg_hideClockWhenIdle = false;
        }

        KCM.SettingHighlighter {
            id: clockAlwaysHighlighter
            highlight: configForm.cfg_alwaysShowClock != configForm.cfg_alwaysShowClockDefault
                || configForm.cfg_hideClockWhenIdle != configForm.cfg_hideClockWhenIdleDefault
        }
    }

    QQC2.RadioButton {
        text: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "On unlocking prompt")
        checked: configForm.cfg_alwaysShowClock && configForm.cfg_hideClockWhenIdle
        onToggled: {
            configForm.cfg_alwaysShowClock = true;
            configForm.cfg_hideClockWhenIdle = true;
        }

        KCM.SettingHighlighter {
            highlight: clockAlwaysHighlighter.highlight
        }
    }

    QQC2.RadioButton {
        text: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Never")
        checked: !configForm.cfg_alwaysShowClock
        onToggled: {
            configForm.cfg_alwaysShowClock = false;
        }

        KCM.SettingHighlighter {
            highlight: clockAlwaysHighlighter.highlight
        }
    }

    QQC2.CheckBox {
        id: showMediaControls
        Kirigami.FormData.label: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Media controls:")
        text: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Show under unlocking prompt")

        KCM.SettingHighlighter {
            highlight: configForm.cfg_showMediaControlsDefault != configForm.cfg_showMediaControls
        }
    }
}
