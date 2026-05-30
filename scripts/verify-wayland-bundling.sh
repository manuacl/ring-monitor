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

# The load-bearing native-Wayland artifacts. Checked by basename (find,
# not a fixed path) so the lib-vs-lib/<triplet> layout doesn't matter:
#   - libqwayland-generic.so   the wayland QPA platform plugin (so
#                              QT_QPA_PLATFORM=wayland works at all)
#   - libqwayland-egl.so       the GPU-accelerated variant Qt picks on
#                              most KWin/sway boxes — a silently dropped
#                              egl plugin must fail HERE, not at launch
#   - libLayerShellQtInterface.so.6  the per-window wlr-layer-shell
#                              integration (compiled in, NOT the dlopened
#                              `liblayer-shell.so` plugin, which the global
#                              useLayerShell path would use — we don't)
required=(
    libqwayland-generic.so
    libqwayland-egl.so
    libLayerShellQtInterface.so.6
)
missing=0
for n in "${required[@]}"; do
    if ! find squashfs-root -name "$n" 2>/dev/null | grep -q .; then
        echo "::error::missing from AppImage: $n"
        missing=1
    fi
done
rm -rf squashfs-root
[ "$missing" -eq 0 ] && echo "Native-Wayland artifacts bundled OK"
exit "$missing"
