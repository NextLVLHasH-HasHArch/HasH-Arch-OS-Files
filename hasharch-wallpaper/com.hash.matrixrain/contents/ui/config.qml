/*
 * Desktop wallpaper settings UI (right-click desktop -> Configure -> Wallpaper).
 * Lets the user pick Live weather vs Code rain, and set the location/units.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: cfg
    twinFormLayouts: parentLayout

    property string cfg_mode
    property string cfg_modeDefault: "weather"
    property string cfg_locationName
    property string cfg_locationNameDefault: "Manchester"
    property string cfg_units
    property string cfg_unitsDefault: "metric"
    property real   cfg_fixedLatitude
    property real   cfg_fixedLatitudeDefault: -999
    property real   cfg_fixedLongitude
    property real   cfg_fixedLongitudeDefault: -999
    property string cfg_forceCondition
    property string cfg_forceConditionDefault: "auto"
    property bool   cfg_showInfo
    property bool   cfg_showInfoDefault: true

    QQC2.ComboBox {
        id: modeBox
        Kirigami.FormData.label: i18n("Background:")
        model: [
            { text: i18n("Live weather"), value: "weather" },
            { text: i18n("Code rain"),    value: "code" }
        ]
        textRole: "text"
        valueRole: "value"
        currentIndex: cfg.cfg_mode === "code" ? 1 : 0
        onActivated: cfg.cfg_mode = currentValue
    }

    // Location with live city suggestions (Open-Meteo geocoding). A plain text
    // field holds what the user types (never overwritten by the suggestion list);
    // suggestions appear in a popup below, and picking one stores exact coords.
    QQC2.TextField {
        id: locField
        Kirigami.FormData.label: i18n("Location:")
        enabled: cfg.cfg_mode === "weather"
        Layout.fillWidth: true
        placeholderText: i18n("Type a city…")
        Component.onCompleted: text = cfg.cfg_locationName   // init once (no binding to overwrite typing)

        Timer { id: debounce; interval: 350; onTriggered: locField.search(locField.text) }

        // onTextEdited fires ONLY for real user keystrokes, not programmatic text changes,
        // so accepting a suggestion (which sets .text) never re-triggers a search.
        onTextEdited: {
            cfg.cfg_locationName = text;
            cfg.cfg_fixedLatitude = -999;     // typed, not picked -> geocode by name
            cfg.cfg_fixedLongitude = -999;
            debounce.restart();
        }

        function search(q) {
            if (!q || q.trim().length < 2) { suggModel.clear(); suggPopup.close(); return; }
            var xhr = new XMLHttpRequest();
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return;
                suggModel.clear();
                if (xhr.status === 200) {
                    try {
                        var rs = (JSON.parse(xhr.responseText).results) || [];
                        for (var i = 0; i < rs.length; i++) {
                            var r = rs[i];
                            var place = r.name + (r.admin1 ? ", " + r.admin1 : "")
                                      + (r.country_code ? ", " + r.country_code : "");
                            suggModel.append({ label: place, lat: r.latitude, lon: r.longitude,
                                               cityname: r.name + (r.country_code ? ", " + r.country_code : "") });
                        }
                    } catch (e) { }
                }
                if (suggModel.count > 0 && locField.activeFocus) suggPopup.open();
                else suggPopup.close();
            };
            xhr.open("GET", "https://geocoding-api.open-meteo.com/v1/search?count=6&language=en&name="
                     + encodeURIComponent(q.trim()));
            xhr.send();
        }

        QQC2.Popup {
            id: suggPopup
            y: locField.height + 2
            width: locField.width
            padding: 1
            closePolicy: QQC2.Popup.CloseOnPressOutside | QQC2.Popup.CloseOnEscape
            contentItem: ListView {
                implicitHeight: Math.min(contentHeight, 220)
                model: ListModel { id: suggModel }
                clip: true
                delegate: QQC2.ItemDelegate {
                    required property int index
                    required property var model
                    width: ListView.view.width
                    text: model.label
                    onClicked: {
                        locField.text = model.cityname;       // fill the field (no onTextEdited)
                        cfg.cfg_locationName = model.cityname;
                        cfg.cfg_fixedLatitude = model.lat;     // store exact coordinates
                        cfg.cfg_fixedLongitude = model.lon;
                        suggPopup.close();
                    }
                }
            }
        }
    }

    QQC2.ComboBox {
        Kirigami.FormData.label: i18n("Units:")
        enabled: cfg.cfg_mode === "weather"
        model: [
            { text: i18n("Celsius (°C)"),    value: "metric" },
            { text: i18n("Fahrenheit (°F)"), value: "imperial" }
        ]
        textRole: "text"
        valueRole: "value"
        currentIndex: cfg.cfg_units === "imperial" ? 1 : 0
        onActivated: cfg.cfg_units = currentValue
    }

    QQC2.ComboBox {
        id: condBox
        Kirigami.FormData.label: i18n("Condition (this screen):")
        enabled: cfg.cfg_mode === "weather"
        model: [
            { text: i18n("Auto (real weather)"), value: "auto" },
            { text: i18n("Sun"),                 value: "sun" },
            { text: i18n("Clear night"),         value: "night" },
            { text: i18n("Clouds"),              value: "clouds" },
            { text: i18n("Rain"),                value: "rain" },
            { text: i18n("Snow"),                value: "snow" },
            { text: i18n("Thunderstorm"),        value: "thunder" },
            { text: i18n("Fog"),                 value: "fog" }
        ]
        textRole: "text"
        valueRole: "value"
        Component.onCompleted: currentIndex = Math.max(0, indexOfValue(cfg.cfg_forceCondition))
        onActivated: cfg.cfg_forceCondition = currentValue
    }

    QQC2.CheckBox {
        Kirigami.FormData.label: i18n("Show temperature:")
        text: i18n("Display temperature and location on this screen")
        enabled: cfg.cfg_mode === "weather"
        checked: cfg.cfg_showInfo
        onToggled: cfg.cfg_showInfo = checked
    }
}
