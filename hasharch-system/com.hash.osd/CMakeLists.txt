# HasH-OSD — STANDALONE build of our fork of the Plasma media controller applet
# (forked from plasma-workspace applets/mediacontroller v6.6.5 so we can extend it
# in C++/QML). Uses libplasma's plasma_add_applet macro.
#
#   cmake -B build -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release
#   cmake --build build && sudo cmake --install build
cmake_minimum_required(VERSION 3.16)
project(hash-osd VERSION 1.0 LANGUAGES C CXX)

set(KF_MIN_VERSION 6.0.0)
set(QT_MIN_VERSION 6.6.0)

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
list(APPEND CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Quick Qml)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS Config CoreAddons I18n)
find_package(Plasma REQUIRED)

# Work around qmlcachegen crashing during the build on older Qt (as upstream does)
if (Qt6_VERSION VERSION_LESS "6.9.2")
    set(QML_ARGS NO_CACHEGEN)
endif()

# QML now lives under contents/ui/ (standard package layout)
plasma_add_applet(com.hash.osd
    QML_SOURCES
        contents/ui/main.qml
        contents/ui/AlbumArtStackView.qml
        contents/ui/CompactRepresentation.qml
        contents/ui/ExpandedRepresentation.qml
    CPP_SOURCES
        globalconfig.cpp
    GENERATE_APPLET_CLASS
    QML_ARGS ${QML_ARGS}
)
