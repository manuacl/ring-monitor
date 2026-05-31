cmake_minimum_required(VERSION 3.16)

# Single source of truth for the version: parse KPlugin.Version out
# of metadata.json — the one file the release pipeline
# (.github/workflows/version.yml) bumps. Before this, both the
# project(VERSION ...) below and setApplicationVersion() in main.cpp
# hardcoded "0.5.0" and silently drifted while metadata.json moved on
# (the standalone About tab + `--version` reported the stale number).
# Regex parse (not string(JSON ...)) keeps us on the 3.16 minimum.
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json" _ring_monitor_metadata)
string(REGEX MATCH "\"Version\"[ \t]*:[ \t]*\"([0-9]+\\.[0-9]+\\.[0-9]+)\""
       _ "${_ring_monitor_metadata}")
if(NOT CMAKE_MATCH_1)
    message(FATAL_ERROR
        "ring-monitor: could not parse KPlugin.Version from metadata.json")
endif()
set(RING_MONITOR_VERSION "${CMAKE_MATCH_1}")

project(ring-monitor-standalone
    VERSION ${RING_MONITOR_VERSION}
    LANGUAGES CXX
    DESCRIPTION "Standalone build of ring-monitor (Linux desktop widget)"
)

# C++17 for QML 6.
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# AUTOMOC scans every translation unit for `Q_OBJECT` /
# `QML_ELEMENT` and runs `moc` on the matching headers. The
# QObject subclasses live in `standalone/*.{cpp,h}` —
# `proc_reader`, `autostart`, `window_anchor` are all
# `QObject` + `QML_ELEMENT` for QML registration.
set(CMAKE_AUTOMOC ON)

# Qt 6.6 minimum: the rings render with Shape.CurveRenderer /
# preferredRendererType (core/Ring.qml, core/ConcentricArc.qml), both
# added in Qt 6.6 — on 6.5 the QML fails to load ("Cannot assign to
# non-existent property preferredRendererType"). qt_add_qml_module +
# loadFromModule() (the compile-QML-into-the-binary path used below)
# are 6.5, but CurveRenderer is the binding floor.
# Network provides QLocalServer/QLocalSocket — the single-instance guard +
# wake-up IPC in single_instance.cpp (issues #103 / #104).
find_package(Qt6 6.6 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Network)

# XCB is used by desktop_hints.cpp for the X11/XWayland EWMH hints
# (sticky, skip-taskbar, skip-pager). The Qt 6 native interface gives
# us the xcb_connection_t; we still need the xcb headers + lib to
# call xcb_intern_atom / xcb_send_event directly. pkg-config keeps
# this portable across Linux distros (Fedora, Debian, Arch).
find_package(PkgConfig REQUIRED)
pkg_check_modules(XCB REQUIRED IMPORTED_TARGET xcb)

# Optional native Wayland integration. layer-shell-qt (KDE) lets the
# standalone window become a wlr-layer-shell `bottom`-layer surface on
# wlroots / KWin Wayland — no Alt+Tab, no input capture, unlike the
# XWayland-fallback NORMAL window. OPTIONAL on purpose: a dev box without
# layer-shell-qt (it's an rpm-ostree layer + reboot on the maintainer's
# host) still builds an X11/XWayland-only binary that behaves identically
# (HAVE_LAYER_SHELL_QT undefined → WaylandLayerShell::active() is false →
# the layer path is never taken). The AppImage CI compiles it from source
# into the Qt prefix (scripts/build-layer-shell-qt.sh) so the shipped
# artifact carries the native path.
find_package(LayerShellQt QUIET)
if(LayerShellQt_FOUND)
    message(STATUS "ring-monitor: layer-shell-qt found — native Wayland (wlr-layer-shell) path ENABLED")
else()
    message(STATUS "ring-monitor: layer-shell-qt NOT found — building X11/XWayland-only (native Wayland path disabled)")
endif()

qt_standard_project_setup(REQUIRES 6.6)

# ── Standalone executable ───────────────────────────────────────────
#
# Only the standalone target lives here. The Plasma .plasmoid build
# is owned by plasmapkg2 / kpackagetool6 (no CMake involvement) and
# is unaffected by anything in this file. Future work: add a CMake
# option STANDALONE_ONLY=OFF that also packages the .plasmoid, so a
# single `cmake --install` ships both.
qt_add_executable(ring-monitor-standalone
    standalone/main.cpp
    standalone/desktop_hints.cpp
    standalone/desktop_hints.h
    # Single-instance guard + wake-up IPC (issues #103 / #104). Not a
    # QML_ELEMENT (instantiated in main.cpp, exposed as a context property),
    # so it lives here rather than in the qml_module SOURCES.
    standalone/single_instance.cpp
    standalone/single_instance.h
)

# Bundle the QML as a compiled resource under the
# `RingMonitor.Standalone` URI, loadable from C++ via
# `engine.loadFromModule(...)`. Cleaner than runtime path lookup and
# works identically in a build dir and in an installed AppImage.
#
# C++ classes carrying the `QML_ELEMENT` macro get registered to the
# module automatically when their .cpp lands in SOURCES — that's how
# `ProcReader` becomes available as `import RingMonitor.Standalone;
# ProcReader { ... }`.
qt_add_qml_module(ring-monitor-standalone
    URI RingMonitor.Standalone
    VERSION 1.0
    SOURCES
        standalone/proc_reader.cpp
        standalone/proc_reader.h
        standalone/autostart.cpp
        standalone/autostart.h
        standalone/window_anchor.cpp
        standalone/window_anchor.h
        standalone/nvml_reader.cpp
        standalone/nvml_reader.h
        standalone/wayland_layer_shell.cpp
        standalone/wayland_layer_shell.h
    QML_FILES
        contents/ui/platforms/standalone/Main.qml
        contents/ui/platforms/standalone/SettingsOnlyRoot.qml
        contents/ui/platforms/standalone/MetricsBackend.qml
        contents/ui/platforms/standalone/Theme.qml
        contents/ui/platforms/standalone/ThemedIcon.qml
        contents/ui/platforms/standalone/ConfigStore.qml
        contents/ui/platforms/standalone/SettingsDialog.qml
        contents/ui/platforms/standalone/ColorPicker.qml
        contents/ui/platforms/standalone/ProcStatParser.js
        contents/ui/platforms/standalone/MemInfoParser.js
        contents/ui/platforms/standalone/CpuTempDiscovery.js
        contents/ui/platforms/standalone/GpuDiscovery.js
        contents/ui/platforms/standalone/DiskDiscovery.js
        contents/ui/platforms/standalone/WindowPlacement.js
        contents/ui/core/Ring.qml
        contents/ui/core/ConcentricArc.qml
        contents/ui/core/MainContent.qml
        contents/ui/core/DraggableList.qml
        contents/ui/core/MetricRow.qml
        contents/ui/core/PartitionRow.qml
        contents/ui/core/DiskPartitionPicker.qml
        contents/ui/core/AboutBody.qml
        contents/ui/core/AppearanceBody.qml
        contents/ui/core/MetricsBody.qml
        contents/ui/core/UpdateChecker.qml
        contents/ui/core/MetricsCatalog.js
        contents/ui/core/ColorThemes.js
        contents/ui/core/ReorderLogic.js
        contents/ui/core/RingGeometry.js
        contents/ui/core/DiskMetrics.js
        contents/ui/core/UpdateCheck.js
        contents/ui/core/ProcessRanking.js
)

target_link_libraries(ring-monitor-standalone PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Network
    PkgConfig::XCB
    # dlopen/dlsym/dlclose for NvmlReader's runtime load of
    # libnvidia-ml.so.1. ${CMAKE_DL_LIBS} is -ldl on glibc, empty on
    # platforms where dl* live in libc — portable either way.
    ${CMAKE_DL_LIBS}
)

# Native Wayland (wlr-layer-shell) when layer-shell-qt is present. The
# WaylandLayerShell QML singleton is always compiled (so QML always
# loads); HAVE_LAYER_SHELL_QT switches its body + main.cpp's
# useLayerShell() call from no-ops to the real layer-shell calls.
if(LayerShellQt_FOUND)
    target_link_libraries(ring-monitor-standalone PRIVATE LayerShellQt::Interface)
    target_compile_definitions(ring-monitor-standalone PRIVATE HAVE_LAYER_SHELL_QT)
endif()

# Hand the metadata.json version to the C++ side so
# QGuiApplication::setApplicationVersion() (→ Qt.application.version
# → the standalone About tab's localVersion) reports the real
# release instead of a hardcoded literal.
target_compile_definitions(ring-monitor-standalone PRIVATE
    RING_MONITOR_VERSION="${RING_MONITOR_VERSION}"
)

# The QML auto-registration code generated by qt_add_qml_module
# includes our QML_ELEMENT-bearing headers via `<proc_reader.h>`
# (angle-brackets, system include path). Add `standalone/` to the
# include directories so the generated file resolves them.
target_include_directories(ring-monitor-standalone PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/standalone
)

# ── Install rules (AppImage / AppDir layout) ────────────────────────
#
# `cmake --install build --prefix AppDir/usr` lays out the FHS tree an
# AppImage expects:
#   AppDir/usr/bin/ring-monitor-standalone
#   AppDir/usr/share/applications/dev.manuacl.ringmonitor.desktop
#   AppDir/usr/share/icons/hicolor/scalable/apps/dev.manuacl.ringmonitor.svg
# linuxdeploy + linuxdeploy-plugin-qt then consume that AppDir
# (scripts/build-appimage.sh). The qt plugin reads the .desktop's
# Icon= field to find the icon, and bundles the Qt QML plugins
# (QtQuick, QtQuick.Controls, Qt.labs.settings, ...) that
# loadFromModule pulls in at runtime — only OUR QML is in the compiled
# resource, the Qt modules are not. The .desktop + icon live in
# packaging/ (outside contents/) so they never ride along in the
# Plasma .plasmoid zip.
include(GNUInstallDirs)

install(TARGETS ring-monitor-standalone
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
install(FILES packaging/dev.manuacl.ringmonitor.desktop
    DESTINATION ${CMAKE_INSTALL_DATADIR}/applications
)
install(FILES packaging/dev.manuacl.ringmonitor.svg
    DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps
)
