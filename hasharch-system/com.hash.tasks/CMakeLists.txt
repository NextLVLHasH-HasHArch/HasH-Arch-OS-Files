# HasH-Tasks — STANDALONE build of our fork of the Plasma task manager applet
# (forked from plasma-desktop applets/taskmanager v6.6.5 so we can customise it in
# C++/QML and make it our own). Uses libplasma's plasma_add_applet macro.
#
# The C++ backend links several Plasma private libs — all are installed system-wide
# (PlasmaActivities*, KSysGuard, LibNotificationManager, KF6 KIO/Notifications/…).
# The activity-history settings kcfg (kactivitymanagerd_plugins_settings.*) is
# VENDORED here; upstream pulled it from plasma-desktop's kcms/recentFiles.
#
#   cmake -B build -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release
#   cmake --build build && sudo cmake --install build
cmake_minimum_required(VERSION 3.16)
project(hash-tasks VERSION 1.0 LANGUAGES C CXX)

set(KF_MIN_VERSION 6.0.0)
set(QT_MIN_VERSION 6.6.0)

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
list(APPEND CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(ECMQtDeclareLoggingCategory)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Quick Qml)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS
    Config CoreAddons I18n KIO Notifications Service WindowSystem)
find_package(Plasma REQUIRED)
find_package(PlasmaActivities REQUIRED)
find_package(PlasmaActivitiesStats REQUIRED)
find_package(KSysGuard REQUIRED)
find_package(LibNotificationManager REQUIRED)

add_definitions(-DTRANSLATION_DOMAIN=\"plasma_applet_com.hash.tasks\")

# Work around qmlcachegen crashing during the build on older Qt (as upstream does)
if (Qt6_VERSION VERSION_LESS "6.9.2")
    set(QML_ARGS NO_CACHEGEN)
endif()

plasma_add_applet(com.hash.tasks
    QML_SOURCES
        contents/ui/main.qml
        contents/ui/AudioStream.qml
        contents/ui/Badge.qml
        contents/ui/ConfigAppearance.qml
        contents/ui/ConfigBehavior.qml
        contents/ui/config.qml
        contents/ui/ContextMenu.qml
        contents/ui/GroupDialog.qml
        contents/ui/GroupExpanderOverlay.qml
        contents/ui/MouseHandler.qml
        contents/ui/PipeWireThumbnail.qml
        contents/ui/PlayerController.qml
        contents/ui/PulseAudio.qml
        contents/ui/ScrollableTextWrapper.qml
        contents/ui/TaskBadgeOverlay.qml
        contents/ui/TaskList.qml
        contents/ui/TaskProgressOverlay.qml
        contents/ui/Task.qml
        contents/ui/ToolTipDelegate.qml
        contents/ui/ToolTipInstance.qml
        contents/ui/ToolTipWindowMouseArea.qml
        contents/ui/code/LayoutMetrics.js
        contents/ui/code/TaskTools.js
    CPP_SOURCES
        backend.cpp
        smartlauncherbackend.cpp
        smartlauncheritem.cpp
    RESOURCES
        main.xml
    GENERATE_APPLET_CLASS
    QML_ARGS ${QML_ARGS}
)

# activity-history settings class (vendored kcfg + kcfgc)
kconfig_add_kcfg_files(com.hash.tasks kactivitymanagerd_plugins_settings.kcfgc)

ecm_qt_declare_logging_category(com.hash.tasks
    HEADER log_settings.h
    IDENTIFIER TASKMANAGER_DEBUG
    CATEGORY_NAME com.hash.tasks)

target_link_libraries(com.hash.tasks PRIVATE
                      Qt::Core
                      Qt::Qml
                      Qt::Quick
                      Plasma::Activities
                      Plasma::ActivitiesStats
                      KF6::ConfigGui
                      KF6::I18n
                      KF6::KIOCore
                      KF6::KIOGui
                      KF6::KIOFileWidgets   # KFilePlacesModel
                      KF6::Notifications    # KNotificationJobUiDelegate
                      Plasma::Plasma
                      KSysGuard::ProcessCore
                      KF6::Service
                      KF6::WindowSystem
                      PW::LibNotificationManager)

# generated headers (log_settings.h, kactivitymanagerd_plugins_settings.h)
target_include_directories(com.hash.tasks PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
