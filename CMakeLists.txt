cmake_minimum_required(VERSION 3.16)

project(ring-monitor-standalone
    VERSION 0.5.0
    LANGUAGES CXX
    DESCRIPTION "Standalone build of ring-monitor (Linux desktop widget)"
)

# C++17 for QML 6.
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# AUTOMOC for QObject-derived classes (we have none yet, but every Qt
# tutorial keeps this on by default so contributors don't have to
# remember when it kicks in).
set(CMAKE_AUTOMOC ON)

# Qt 6.5+ ships qt_add_qml_module and loadFromModule(), which is the
# modern idiomatic way to ship QML in an executable — no filesystem
# path resolution at runtime, the QML is compiled into the binary as
# a resource.
find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick)

qt_standard_project_setup(REQUIRES 6.5)

# ── Standalone executable ───────────────────────────────────────────
#
# Only the standalone target lives here. The Plasma .plasmoid build
# is owned by plasmapkg2 / kpackagetool6 (no CMake involvement) and
# is unaffected by anything in this file. Future work: add a CMake
# option STANDALONE_ONLY=OFF that also packages the .plasmoid, so a
# single `cmake --install` ships both.
qt_add_executable(ring-monitor-standalone
    standalone/main.cpp
)

# Bundle the QML as a compiled resource under the
# `RingMonitor.Standalone` URI, loadable from C++ via
# `engine.loadFromModule(...)`. Cleaner than runtime path lookup and
# works identically in a build dir and in an installed AppImage.
qt_add_qml_module(ring-monitor-standalone
    URI RingMonitor.Standalone
    VERSION 1.0
    QML_FILES
        contents/ui/platforms/standalone/Main.qml
)

target_link_libraries(ring-monitor-standalone PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
)
