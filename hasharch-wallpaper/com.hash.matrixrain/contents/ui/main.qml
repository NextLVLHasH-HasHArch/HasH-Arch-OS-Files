/*
 * Plasma 6 wallpaper plugin entry point (desktop + lock screen).
 * Root must be a WallpaperItem (the shell sizes it); config is root.configuration.
 * Switches between the live weather scene and code rain based on "mode".
 */
import QtQuick
import org.kde.plasma.plasmoid
import "."

WallpaperItem {
    id: root

    Loader {
        anchors.fill: parent
        sourceComponent: root.configuration.mode === "code" ? codeComponent : weatherComponent
    }

    Component {
        id: codeComponent
        MatrixRain {
            paused: root.configuration.paused
        }
    }

    Component {
        id: weatherComponent
        WeatherScene {
            locationName: root.configuration.locationName
            fixedLatitude: root.configuration.fixedLatitude
            fixedLongitude: root.configuration.fixedLongitude
            units: root.configuration.units
            forceCondition: root.configuration.forceCondition
            showInfo: root.configuration.showInfo
            showClock: root.configuration.showClock
            paused: root.configuration.paused
            rainColor: root.configuration.rainColor
            cachedTemperature: root.configuration.cachedTemperature
            cachedPlace: root.configuration.cachedPlace
        }
    }

    // Music visualizer (primary screen only), drawn over the background at
    // bottom-center. Hidden while a fullscreen app has paused the wallpaper.
    MusicWave {
        anchors.fill: parent       // full area so the line can wrap around the dock
        visible: root.configuration.showVisualizer && !root.configuration.paused
        paused: root.configuration.paused || !visible
        dockCenter: root.configuration.dockCenter   // live dock geometry (screen-local px)
        dockWidth: root.configuration.dockWidth      // pushed by the wallpaperguard KWin script
        colorMode: root.configuration.visualizerColor
    }
}
