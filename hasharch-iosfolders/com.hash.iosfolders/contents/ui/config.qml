import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: cfg
    property string cfg_group
    property string cfg_groupDefault: "Games"

    QQC2.ComboBox {
        Kirigami.FormData.label: i18n("Show group:")
        editable: true
        model: ["Games", "Media", "Internet", "Development", "Graphics", "Office", "Utilities", "Other"]
        editText: cfg.cfg_group
        onEditTextChanged: cfg.cfg_group = editText
    }
}
