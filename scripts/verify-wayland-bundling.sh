#!/usr/bin/env bash
#
# Verify the standalone AppImage actually bundled the native-Wayland
# pieces (issue #7, PR C2). The offscreen smoke-test runs the
# xcb/offscreen path, so it CANNOT catch a missing Wayland plugin — this
# extracts the built AppImage and asserts the wlr-layer-shell stack is
# present in the AppDir.
#
# Single source of truth, called by BOTH .github/workflows/ci.yml and
# release.yml (the assertion used to be copy-pasted inline in each — the
# egl-plugin addition had to be hand-synced across the two, exactly the
# drift this extraction removes). Run from anywhere after
# scripts/build-appimage.sh; resolves the AppImage at the repo root.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

shopt -s nullglob
appimages=(Ring_Monitor-*-x86_64.AppImage)
if [ "${#appimages[@]}" -eq 0 ]; then
    echo "::error::no Ring_Monitor-*-x86_64.AppImage at repo root (run scripts/build-appimage.sh first)"
    exit 1
fi
appimage="${appimages[0]}"

# --appimage-extract is handled by the AppImage runtime before any mount,
# so it needs no FUSE (CI containers / minimal hosts lack it).
rm -rf squashfs-root
"./$appimage" --appimage-extract >/dev/null

# The two wayland platform plugins requested in build-appimage.sh
# (EXTRA_PLATFORM_PLUGINS) plus layer-shell-qt's shell-integration plugin
# (dlopen'd at runtime, staged by hand in build-appimage.sh because
# linuxdeploy can't see it). egl is checked too: Qt picks it on
# GPU-accelerated Wayland (the common KWin/sway case), so a silently
# dropped egl plugin must fail HERE, not at the user's first launch.
required=(
    usr/plugins/platforms/libqwayland-generic.so
    usr/plugins/platforms/libqwayland-egl.so
    usr/plugins/wayland-shell-integration/libqt-shell-integration-layer.so
)
missing=0
for f in "${required[@]}"; do
    if ! ls "squashfs-root/$f" >/dev/null 2>&1; then
        echo "::error::missing from AppImage: $f"
        missing=1
    fi
done
rm -rf squashfs-root
[ "$missing" -eq 0 ] && echo "Native-Wayland plugins bundled OK"
exit "$missing"
