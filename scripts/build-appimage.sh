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

# 2b. Make layer-shell-qt's interface lib discoverable to linuxdeploy
# (PR C2, native Wayland). We use the PER-WINDOW path
# (LayerShellQt::Window::get → setShellIntegration), whose wlr-layer-shell
# integration is compiled INTO libLayerShellQtInterface.so — NOT the
# dlopened `liblayer-shell.so` shell-integration plugin (that's only for
# the global QT_WAYLAND_SHELL_INTEGRATION=layer-shell path, which we don't
# use). So the load-bearing artifact is the interface lib, a NEEDED dep of
# our binary that linuxdeploy resolves automatically — EXCEPT
# build-layer-shell-qt.sh installs it under the Qt prefix's lib/<triplet>/
# subdir (KDE_INSTALL_USE_QT_SYS_PATHS layout) that linuxdeploy doesn't
# search. Point LD_LIBRARY_PATH at its real dir so the NEEDED-dep lookup
# finds it. No-op locally (QT_ROOT_DIR unset → the system lib is on the
# default search path, and an X11-only build links no such lib anyway).
if [ -n "${QT_ROOT_DIR:-}" ]; then
    iface="$(find "$QT_ROOT_DIR/lib" -name 'libLayerShellQtInterface.so.6' 2>/dev/null | head -1)"
    if [ -n "$iface" ]; then
        export LD_LIBRARY_PATH="$(dirname "$iface"):${LD_LIBRARY_PATH:-}"
        echo "layer-shell-qt interface lib: $iface (added to LD_LIBRARY_PATH for linuxdeploy)"
    else
        echo "build-appimage: libLayerShellQtInterface.so.6 not found under $QT_ROOT_DIR/lib — AppImage will be X11/XWayland-only"
    fi
fi

# 2c. Bundle the wayland-egl CLIENT-BUFFER integration plugin (issue #110).
#
# linuxdeploy-plugin-qt ships the wayland PLATFORM plugins (platforms/
# libqwayland-egl.so), the shell-integration and the decoration-client dirs —
# but NOT plugins/wayland-graphics-integration-client/, which holds
# libqt-plugin-wayland-egl.so. That plugin is what registers the "wayland-egl"
# client-buffer integration the native-Wayland (wlr-layer-shell, PR C2) path
# needs to get a GL surface. Without it Qt enumerates zero client-buffer
# integrations on a KWin-Wayland session (`Available client buffer integrations:
# QList()`), QRhiGles2 can't create a context, and the binary SIGABRTs at
# launch. The egl PLATFORM plugin being present (and passing the old verify
# gate) is NOT the same artifact — note the lib it registers,
# libQt6WaylandEglClientHwIntegration.so, was already bundled; only its
# registering plugin was missing. Copy the whole dir (egl + dmabuf/drm
# siblings) into the AppDir BEFORE linuxdeploy runs so it packages the plugins
# and resolves their NEEDED deps. The XWayland (xcb) and software-backend paths
# don't touch it, which is why offscreen CI and xcb checks stayed green.
QT_PLUGINS="$(qmake -query QT_INSTALL_PLUGINS 2>/dev/null \
    || qmake6 -query QT_INSTALL_PLUGINS 2>/dev/null || true)"
gfx_src="${QT_PLUGINS:+$QT_PLUGINS/wayland-graphics-integration-client}"
if [ -n "$gfx_src" ] && [ -d "$gfx_src" ]; then
    mkdir -p AppDir/usr/plugins/wayland-graphics-integration-client
    cp -a "$gfx_src/." AppDir/usr/plugins/wayland-graphics-integration-client/
    echo "Bundled wayland-graphics-integration-client from $gfx_src"
else
    echo "build-appimage: wayland-graphics-integration-client not found (QT_INSTALL_PLUGINS=${QT_PLUGINS:-unset}) — AppImage will SIGABRT on native Wayland (issue #110)"
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
# platform plugins (so QT_QPA_PLATFORM=wayland works), and EXTRA_QT_MODULES
# pulls in libQt6WaylandClient (+ the wayland integration plugins it needs)
# — which libLayerShellQtInterface.so also links. With the interface lib
# itself resolved via LD_LIBRARY_PATH (step 2b), this lets the AppImage run
# as a wlr-layer-shell surface on KWin/sway/Hyprland. Harmless on an
# X11-only host: the plugins ride along unused.
export EXTRA_PLATFORM_PLUGINS="libqwayland-generic.so;libqwayland-egl.so"
export EXTRA_QT_MODULES="waylandclient"

"$TOOLS/linuxdeploy-x86_64.AppImage" \
    --appdir AppDir \
    --plugin qt \
    --output appimage

echo "Built $LDAI_OUTPUT"
