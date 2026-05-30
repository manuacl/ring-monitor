#!/usr/bin/env bash
#
# Build the portable standalone AppImage (issue #7, PR H).
#
# Single source of truth for the AppImage build — driven by CI
# (.github/workflows/ci.yml smoke-build + release.yml attach) and
# runnable locally. Produces Ring_Monitor-<version>-x86_64.AppImage at
# the repo root.
#
# Prereqs on PATH: cmake (>= 3.16), a C++17 compiler, pkg-config, the
# xcb dev headers, and a Qt >= 6.6 install (the rings need
# Shape.CurveRenderer) exposing qmake + qmlimportscanner (distro Qt
# locally; aqtinstall in CI). curl for the linuxdeploy download.
#
# Portability note: the resulting AppImage is only as portable as the
# glibc of the build host — build on the OLDEST target glibc (CI uses
# ubuntu-22.04 / glibc 2.35), never a bleeding-edge distro, or it will
# refuse to start on older boxes. See docs/releasing.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Version is single-sourced from metadata.json (KPlugin.Version), the
# same file CMakeLists.txt parses — they always agree.
VERSION="$(grep -oP '"Version"\s*:\s*"\K[0-9]+\.[0-9]+\.[0-9]+' metadata.json)"
echo "Building AppImage for ring-monitor $VERSION"

# 1. Configure + build (Release).
#
# Bound the job count explicitly. `--parallel` with NO number passes a
# bare `-j` to Make = UNBOUNDED — and qt_add_qml_module emits one C++
# TU per QML file (~40 here), so an unbounded build spawns dozens of
# cc1plus at once and can OOM a memory-constrained dev box. Cap at
# nproc, and honor CMAKE_BUILD_PARALLEL_LEVEL when the caller wants
# fewer (e.g. `CMAKE_BUILD_PARALLEL_LEVEL=4 scripts/build-appimage.sh`).
cmake -B build -S . -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel "${CMAKE_BUILD_PARALLEL_LEVEL:-$(nproc)}"

# 2. Stage the AppDir via the CMake install rules.
rm -rf AppDir
cmake --install build --prefix AppDir/usr

# 2b. Stage layer-shell-qt's shell-integration plugin (PR C2, native
# Wayland). linuxdeploy-plugin-qt bundles the wayland PLATFORM plugin
# (requested via EXTRA_* below) but NOT this one: Qt's wayland plugin
# dlopens it at runtime, so it's not a NEEDED lib and the scanner can't
# see it. Copy it into the AppDir before linuxdeploy runs so linuxdeploy
# patches its rpath and pulls its NEEDED libs (libLayerShellQtInterface,
# QtWaylandClient) along. Best-effort: absent on a local X11-only build
# (no layer-shell-qt) → skip, and the AppImage is X11/XWayland-only.
QT_PLUGINS_DIR=""
if [ -n "${QT_ROOT_DIR:-}" ] && [ -d "$QT_ROOT_DIR/plugins" ]; then
    QT_PLUGINS_DIR="$QT_ROOT_DIR/plugins"
elif command -v qmake6 >/dev/null 2>&1; then
    QT_PLUGINS_DIR="$(qmake6 -query QT_INSTALL_PLUGINS 2>/dev/null || true)"
elif command -v qmake >/dev/null 2>&1; then
    QT_PLUGINS_DIR="$(qmake -query QT_INSTALL_PLUGINS 2>/dev/null || true)"
fi
layer_plugin="${QT_PLUGINS_DIR:+$QT_PLUGINS_DIR/wayland-shell-integration/libqt-shell-integration-layer.so}"
if [ -n "$layer_plugin" ] && [ -f "$layer_plugin" ]; then
    mkdir -p AppDir/usr/plugins/wayland-shell-integration
    cp -v "$layer_plugin" AppDir/usr/plugins/wayland-shell-integration/
    echo "Staged layer-shell shell-integration plugin — native Wayland path bundled"
else
    echo "build-appimage: layer-shell-qt plugin not found (looked in '${QT_PLUGINS_DIR:-<no Qt plugins dir>}') — AppImage will be X11/XWayland-only"
fi

# 3. Fetch linuxdeploy + the qt plugin (cached between runs).
TOOLS="$ROOT/.appimage-tools"
mkdir -p "$TOOLS"
# Download to a temp path and only move into place on success, so an
# interrupted/partial download never leaves a corrupt file that the
# existence-only cache guard would then trust forever.
fetch() {
    local dest="$TOOLS/$1"
    [ -x "$dest" ] && return 0
    curl -fsSL "$2" -o "$dest.part"
    chmod +x "$dest.part"
    mv "$dest.part" "$dest"
}
fetch linuxdeploy-x86_64.AppImage \
    https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
fetch linuxdeploy-plugin-qt-x86_64.AppImage \
    https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage

# 4. Build the AppImage.
#
# QML_SOURCES_PATHS tells linuxdeploy-plugin-qt where to scan for
# `import` statements. Our QML is compiled into the binary
# (qt_add_qml_module + loadFromModule), so it is NOT on disk for the
# plugin's qmlimportscanner to find — without this it bundles zero QML
# plugins and the app dies at runtime with `module "QtQuick" is not
# installed`. Scan ONLY the dirs the standalone binary actually loads
# (core + standalone); pointing it at platforms/plasma/ would feed the
# scanner org.kde.plasma.* / ksysguard imports the standalone build
# never uses (and the CI Qt can't resolve). Kirigami imports here are
# satisfied by the Kirigami installed into the Qt prefix
# (scripts/build-kirigami6.sh in CI; the system Kirigami locally).
export QML_SOURCES_PATHS="$ROOT/contents/ui/core:$ROOT/contents/ui/platforms/standalone"
# Run the helper AppImages without FUSE (CI containers / minimal hosts
# often lack it; harmless when FUSE is present).
export APPIMAGE_EXTRACT_AND_RUN=1
# LDAI_OUTPUT is the current name the appimage output plugin reads for
# the target filename; OUTPUT is its legacy alias. Set both so the
# upload globs (Ring_Monitor-*-x86_64.AppImage) match regardless of
# which the pinned-to-`continuous` plugin honors.
export LDAI_OUTPUT="Ring_Monitor-${VERSION}-x86_64.AppImage"
export OUTPUT="$LDAI_OUTPUT"

# Native Wayland (PR C2): linuxdeploy-plugin-qt bundles only the xcb
# platform plugin by default. EXTRA_PLATFORM_PLUGINS adds the wayland
# platform plugins, and EXTRA_QT_MODULES pulls in libQt6WaylandClient
# (+ the wayland-graphics/decoration integration plugins it needs).
# Together with the shell-integration plugin staged in step 2b, this
# lets the AppImage run as a wlr-layer-shell surface on KWin/sway/
# Hyprland Wayland. Harmless on an X11-only host: the plugins ride
# along unused.
export EXTRA_PLATFORM_PLUGINS="libqwayland-generic.so;libqwayland-egl.so"
export EXTRA_QT_MODULES="waylandclient"

"$TOOLS/linuxdeploy-x86_64.AppImage" \
    --appdir AppDir \
    --plugin qt \
    --output appimage

echo "Built $LDAI_OUTPUT"
