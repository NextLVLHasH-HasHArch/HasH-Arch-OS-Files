/*
 * WeatherScene.qml — live, animated weather background, rendered on the GPU.
 *
 * The visuals are a single procedural fragment shader (weather.frag.qsb) driven
 * by uniforms, so the GPU renders every condition at vsync with near-zero CPU.
 * Data/networking (location + Open-Meteo) stays here in QML.
 */
import QtQuick
import Qt5Compat.GraphicalEffects

Item {
    id: scene

    // ---- inputs ----
    property real   fixedLatitude:  -999
    property real   fixedLongitude: -999
    property string locationName:   ""
    property string units:          "metric"
    property real   fps:            60       // GPU renders at vsync; kept for compatibility
    property bool   showInfo:       true
    property bool   showClock:      true     // big centred desktop clock (off on the lock screen)
    property bool   paused:         false
    property color  rainColor:      "#9cddec"   // configurable rain droplet colour
    // Cached weather pushed into the lock config by hash-weather-sync, used when
    // this instance has no live fetch (e.g. the screen-locker greeter).
    property real   cachedTemperature: -999
    property string cachedPlace:       ""
    // Random seed chosen once at startup; randomises the night-sky starfield so it
    // looks natural (and differs per screen) instead of a fixed repeating pattern.
    readonly property real starSeed: Math.random() * 1000.0

    // auto | sun | night | clouds | rain | snow | thunder | fog
    property string forceCondition: "auto"

    // ---- resolved state ----
    property string condition: "clear"
    property string realCondition: "clear"
    property bool   isDay:     true
    property real   windFactor: 0.0
    property real   temperature: NaN
    property string placeLabel: ""
    property bool   ready: false

    // condition string -> shader index (0 clear,1 clouds,2 rain,3 snow,4 storm,5 fog)
    readonly property int conditionIndex: {
        switch (condition) {
        case "clouds": return 1;
        case "rain":   return 2;
        case "snow":   return 3;
        case "storm":  return 4;
        case "fog":    return 5;
        default:       return 0;
        }
    }

    // ---------- networking ----------
    function getJSON(url, ok) {
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try { ok(JSON.parse(xhr.responseText)); }
                    catch (e) { console.log("WeatherScene parse error:", e); }
                } else {
                    console.log("WeatherScene HTTP", xhr.status, url);
                }
            }
        };
        xhr.open("GET", url);
        xhr.send();
    }

    function resolveLocation() {
        if (fixedLatitude > -900 && fixedLongitude > -900) {
            fetchWeather(fixedLatitude, fixedLongitude, placeLabel || locationName);
        } else if (locationName.length > 0) {
            getJSON("https://geocoding-api.open-meteo.com/v1/search?count=1&language=en&name="
                    + encodeURIComponent(locationName),
                function(d) {
                    if (d.results && d.results.length) {
                        var r = d.results[0];
                        fetchWeather(r.latitude, r.longitude,
                                     r.name + (r.country_code ? ", " + r.country_code : ""));
                    } else { ipLookup(); }
                });
        } else { ipLookup(); }
    }

    function ipLookup() {
        getJSON("http://ip-api.com/json/?fields=status,city,country,lat,lon",
            function(d) {
                if (d.status === "success")
                    fetchWeather(d.lat, d.lon, d.city + (d.country ? ", " + d.country : ""));
            });
    }

    function fetchWeather(lat, lon, label) {
        placeLabel = label || "";
        getJSON("https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon
                + "&current=temperature_2m,weather_code,is_day,wind_speed_10m"
                + "&wind_speed_unit=kmh&temperature_unit="
                + (units === "imperial" ? "fahrenheit" : "celsius") + "&timezone=auto",
            function(d) {
                if (!d.current) return;
                var c = d.current;
                scene.isDay = (c.is_day === 1);
                scene.temperature = c.temperature_2m;
                scene.windFactor = Math.max(0, Math.min(1, (c.wind_speed_10m || 0) / 40.0));
                scene.realCondition = mapWmo(c.weather_code);
                scene.ready = true;
                applyCondition();
            });
    }

    function applyCondition() {
        switch (forceCondition) {
        case "sun":     isDay = true;  condition = "clear"; break;
        case "night":   isDay = false; condition = "clear"; break;
        case "clouds":  condition = "clouds"; break;
        case "rain":    condition = "rain";   break;
        case "snow":    condition = "snow";   break;
        case "thunder": condition = "storm";  break;
        case "fog":     condition = "fog";    break;
        default:        condition = realCondition; break;
        }
    }
    onForceConditionChanged: applyCondition()

    // Re-fetch from the new location as soon as the user updates it in config
    // (coalesced, since locationName + lat + lon may all change together).
    Timer { id: refetch; interval: 400; onTriggered: scene.resolveLocation() }
    onLocationNameChanged: refetch.restart()
    onFixedLatitudeChanged: refetch.restart()
    onFixedLongitudeChanged: refetch.restart()

    function mapWmo(code) {
        if (code === 0 || code === 1) return "clear";
        if (code === 2 || code === 3) return "clouds";
        if (code === 45 || code === 48) return "fog";
        if (code >= 51 && code <= 67) return "rain";
        if (code >= 71 && code <= 77) return "snow";
        if (code >= 80 && code <= 82) return "rain";
        if (code === 85 || code === 86) return "snow";
        if (code >= 95) return "storm";
        return "clouds";
    }

    // ---------- GPU rendering ----------
    ShaderEffect {
        id: fx
        anchors.fill: parent
        fragmentShader: Qt.resolvedUrl("weather.frag.qsb")
        property real time: 0
        property real condition: scene.conditionIndex
        property real isDay: scene.isDay ? 1.0 : 0.0
        property real windFactor: scene.windFactor
        property real aspect: width / Math.max(1.0, height)
        property color rainColor: scene.rainColor
        property real moonPhase: scene.moonPhase
        // Random per-instance seed so each screen draws a different starfield
        // (kept in a sane range; the shader uses it to offset the star grid ids).
        property real starSeed: scene.starSeed
    }
    // Advances the shader clock at 24fps (only while visible & not paused).
    Timer {
        interval: Math.round(1000 / 24)
        running: scene.visible && !scene.paused
        repeat: true
        onTriggered: fx.time += (1.0 / 24.0)
    }

    // ---------- temperature + clock overlay ----------
    property string clockTime: ""
    property string clockDate: ""
    property real   moonPhase: 0.5      // 0=new, 0.25=first qtr, 0.5=full, 0.75=last qtr
    // Current lunar phase from the date (synodic month since a known new moon).
    function computeMoonPhase() {
        var synodic = 29.530588853;
        var knownNew = Date.UTC(2000, 0, 6, 18, 14, 0) / 86400000.0;  // 2000-01-06 new moon
        var nowDays = Date.now() / 86400000.0;
        var ph = ((nowDays - knownNew) % synodic) / synodic;
        if (ph < 0) ph += 1.0;
        return ph;
    }
    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            var d = new Date();
            scene.clockTime = Qt.formatTime(d, "HH:mm");
            scene.clockDate = Qt.formatDate(d, "dddd, d MMMM yyyy");
            scene.moonPhase = scene.computeMoonPhase();
        }
    }
    // Effective values: live fetch if we have it, else the cached lock-screen values.
    readonly property real effTemp: !isNaN(temperature) ? temperature
                                  : (cachedTemperature > -900 ? cachedTemperature : NaN)
    readonly property string effPlace: placeLabel.length ? placeLabel : cachedPlace
    readonly property string tempStr: isNaN(effTemp) ? "" :
                  Math.round(effTemp) + (scene.units === "imperial" ? "°F" : "°C")
    readonly property bool   hasInfo: scene.ready || scene.cachedTemperature > -900

    // DESKTOP — big, centred, lock-screen-style clock with the weather below it
    // (location, then temperature under the location). Hidden on the lock screen,
    // which has KDE's own clock (see showClock).
    Column {
        id: desktopCenter
        visible: scene.showClock
        anchors.horizontalCenter: parent.horizontalCenter
        y: scene.height * 0.13
        spacing: 0
        // exact lock-screen drop shadow (Sweet LockScreenUi.qml clockShadow)
        layer.enabled: true
        layer.effect: DropShadow {
            horizontalOffset: 1
            verticalOffset: 1
            radius: 6
            samples: 14
            spread: 0.3
            color: "black"
        }
        Text {                                                   // time (big, lock-screen style)
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            text: scene.clockTime
            color: "white"
            font.pixelSize: Math.round(scene.height * 0.17)
        }
        Text {                                                   // date
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            text: scene.clockDate
            color: "white"; opacity: 0.95
            font.pixelSize: Math.round(scene.height * 0.040)
        }
        Item { width: 1; height: Math.round(scene.height * 0.025); visible: scene.showInfo && scene.hasInfo }
        Text {                                                   // location
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            visible: scene.showInfo && scene.hasInfo
            text: scene.effPlace
            color: "white"; opacity: 0.95
            font.pixelSize: Math.round(scene.height * 0.030)
        }
        Text {                                                   // temperature, below the location
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            visible: scene.showInfo && scene.hasInfo
            text: scene.tempStr
            color: "white"
            font.pixelSize: Math.round(scene.height * 0.065)
        }
    }

    // LOCK SCREEN — KDE draws its own clock, so we only show temp + place (top-left).
    Column {
        id: lockCorner
        visible: !scene.showClock && scene.showInfo && scene.hasInfo
        x: scene.width * 0.10
        y: scene.height * 0.02
        spacing: 0
        Text {
            text: scene.tempStr
            color: "white"
            font.pixelSize: Math.round(scene.height * 0.07)
            font.weight: Font.Light
            style: Text.Raised; styleColor: "#66000000"
        }
        Text {
            text: scene.effPlace
            color: "white"; opacity: 0.85
            font.pixelSize: Math.round(scene.height * 0.020)
            style: Text.Raised; styleColor: "#66000000"
        }
    }

    Timer {                                  // re-check the weather every hour
        interval: 60 * 60 * 1000; running: true; repeat: true
        onTriggered: scene.resolveLocation()
    }
    Component.onCompleted: { applyCondition(); resolveLocation(); }
    function rebuild() {}   // no-op (shader needs no particle re-init)
}
