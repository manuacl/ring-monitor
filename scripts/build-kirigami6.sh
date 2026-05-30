#!/usr/bin/env bash
#
# Build KDE Kirigami 6 (+ extra-cmake-modules) from source and install
# it into the Qt prefix, so linuxdeploy-plugin-qt can discover and
# bundle org.kde.kirigami into the AppImage (issue #7, PR H).
#
# WHY this exists: the standalone build's shared core/ layer imports
# `org.kde.kirigami` (the one org.kde.* import the plasma-isolation
# invariant allows — Kirigami is a portable KF6 framework). But
# linuxdeploy-plugin-qt bundles only Qt's OWN QML modules, and neither
# aqtinstall nor ubuntu-22.04's apt ships Kirigami 6 — so without this
# the CI AppImage has no Kirigami to bundle and the app dies at launch
# with `module "org.kde.kirigami" is not installed`.
#
# CI-only: a local build on a KF6 distro already has Kirigami on the
# system QML import path, so scripts/build-appimage.sh finds it there
# without this script.
#
# Requires: cmake, a C++17 compiler, git, and a Qt >= 6.5 install whose
# prefix is in $QT_ROOT_DIR (set by jurplel/install-qt-action).
set -euo pipefail

: "${QT_ROOT_DIR:?QT_ROOT_DIR must point at the Qt prefix (set by install-qt-action)}"

# KF6 tags: ECM and Kirigami release together under the same version.
# v6.0.0's floor is Qt 6.5 and it builds fine against the Qt 6.6 the
# workflows install (the app needs 6.6 for Shape.CurveRenderer). Bump in
# lockstep if the aqt Qt version in the workflows is raised further.
KIRIGAMI_VERSION="${KIRIGAMI_VERSION:-v6.0.0}"
JOBS="${CMAKE_BUILD_PARALLEL_LEVEL:-$(nproc)}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

build_kf() {
    local repo="$1" src="$WORK/$1"
    git clone --depth 1 --branch "$KIRIGAMI_VERSION" \
        "https://invent.kde.org/frameworks/$repo.git" "$src"
    # KDE_INSTALL_USE_QT_SYS_PATHS=ON lays the QML module / plugins / libs
    # into Qt's own dir layout under the prefix (qml/, plugins/, lib/),
    # which is exactly where qmlimportscanner + linuxdeploy look — without
    # it ECM would drop them in lib/<triplet>/qml and the scanner misses
    # them. CMAKE_PREFIX_PATH=$QT_ROOT_DIR lets Kirigami find both Qt and
    # the ECM we install in the first pass.
    cmake -S "$src" -B "$src/build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$QT_ROOT_DIR" \
        -DCMAKE_PREFIX_PATH="$QT_ROOT_DIR" \
        -DKDE_INSTALL_USE_QT_SYS_PATHS=ON \
        -DBUILD_TESTING=OFF
    cmake --build "$src/build" --parallel "$JOBS"
    cmake --install "$src/build"
}

build_kf extra-cmake-modules   # Kirigami's build-time dependency
build_kf kirigami

echo "Kirigami $KIRIGAMI_VERSION installed into $QT_ROOT_DIR"
