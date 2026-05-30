#!/usr/bin/env bash
#
# Build KDE layer-shell-qt from source and install it into the Qt
# prefix, so the standalone AppImage can take the native wlr-layer-shell
# path on wlroots / KWin Wayland (issue #7, PR C2).
#
# WHY this exists: `find_package(LayerShellQt)` in CMakeLists.txt is the
# switch for the native Wayland background-layer surface. Neither
# aqtinstall nor ubuntu-22.04's apt ships layer-shell-qt for Qt 6, so
# without this the CI AppImage builds X11/XWayland-only (HAVE_LAYER_SHELL_QT
# undefined) and KWin/sway/Hyprland-Wayland users never get the clean
# layer surface (no Alt+Tab, click pass-through).
#
# CI-only: a local build on a KF6 distro installs layer-shell-qt via the
# package manager (e.g. `kf6-layer-shell-qt-devel`), so CMake finds it on
# the system prefix without this script.
#
# Runs AFTER scripts/build-kirigami6.sh: it reuses the extra-cmake-modules
# that script already installed into $QT_ROOT_DIR. Also requires the Qt 6
# WaylandClient module (aqt `qtwayland`) and the wayland dev stack
# (libwayland-dev, wayland-protocols, libxkbcommon-dev).
#
# Requires: cmake, a C++17 compiler, git, and a Qt >= 6.6 install whose
# prefix is in $QT_ROOT_DIR (set by jurplel/install-qt-action).
set -euo pipefail

: "${QT_ROOT_DIR:?QT_ROOT_DIR must point at the Qt prefix (set by install-qt-action)}"

# layer-shell-qt tags track Plasma releases, NOT the Qt version. The
# v6.0.x line pins QT_MIN_VERSION 6.6.0, so it builds cleanly against the
# Qt 6.6 the workflows install; master/6.6.9x require Qt 6.10. Pin to the
# v6.0 line. Bump in lockstep only if the aqt Qt is raised past what this
# tag supports.
LAYER_SHELL_QT_VERSION="${LAYER_SHELL_QT_VERSION:-v6.0.5}"
JOBS="${CMAKE_BUILD_PARALLEL_LEVEL:-$(nproc)}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SRC="$WORK/layer-shell-qt"
git clone --depth 1 --branch "$LAYER_SHELL_QT_VERSION" \
    https://invent.kde.org/plasma/layer-shell-qt.git "$SRC"

# KDE_INSTALL_USE_QT_SYS_PATHS=ON lays the lib, CMake config, and the
# QML/shell-integration plugin into Qt's own dir layout under the prefix
# — where find_package(LayerShellQt) and qmlimportscanner already look,
# and where build-appimage.sh picks up the shell-integration plugin.
# CMAKE_PREFIX_PATH=$QT_ROOT_DIR lets it find both Qt and the ECM that
# build-kirigami6.sh installed.
cmake -S "$SRC" -B "$SRC/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$QT_ROOT_DIR" \
    -DCMAKE_PREFIX_PATH="$QT_ROOT_DIR" \
    -DKDE_INSTALL_USE_QT_SYS_PATHS=ON \
    -DBUILD_TESTING=OFF
cmake --build "$SRC/build" --parallel "$JOBS"
cmake --install "$SRC/build"

echo "layer-shell-qt $LAYER_SHELL_QT_VERSION installed into $QT_ROOT_DIR"
