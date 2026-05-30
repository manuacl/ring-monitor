#!/usr/bin/env bash
#
# Infer the platform scope of a release from the set of files it changed
# (issue #89). Reads newline-separated paths on STDIN, prints the tag
# suffix on STDOUT:
#
#   -p   the release touched ONLY Plasma-facing code
#   -s   the release touched ONLY standalone-facing code
#   ""   mixed, shared (core/), or ambiguous → notify both platforms
#
# Used by .github/workflows/version.yml to suffix the git tag
# (`v0.8.0-p` / `v0.8.0-s` / `v0.8.0`). The suffix lives on the tag
# ONLY — metadata.json stays a clean X.Y.Z — and the client
# (core/UpdateCheck.js `releaseScope`) reads it to decide which build a
# release notifies.
#
# SAFETY BIAS: a wrong `-p`/`-s` HIDES a real update from the other
# platform (bad); a wrong "" merely over-notifies (harmless). So we emit
# a suffix only when confident the release is single-platform — anything
# touching shared core/, both platforms, or only neutral files (docs,
# CI, tests, build metadata) falls back to "" (both).
#
# Pure + tested: tests/infer-release-scope.test.mjs feeds file lists and
# asserts the suffix. No git calls here — the caller computes the diff
# and pipes it in, so the classifier stays trivially testable.
set -euo pipefail

has_plasma=0
has_standalone=0
has_core=0

# `|| [ -n "$f" ]` processes a final line that lacks a trailing newline
# (read returns non-zero at EOF but still populates $f).
while IFS= read -r f || [ -n "$f" ]; do
    [ -n "$f" ] || continue
    case "$f" in
        # Shared portable layer — affects BOTH artifacts, so a release
        # touching it is never single-platform. Listed first: `case`
        # patterns match across `/`, so the narrowest prefixes win by
        # appearing before the broad `contents/ui/*.qml` fallback.
        contents/ui/core/*) has_core=1 ;;

        # Standalone-only: the C++ entry point + helpers, the standalone
        # QML adapters, the CMake module, the AppImage build scripts, and
        # the packaging assets. None of these ship in the .plasmoid.
        standalone/* | \
        contents/ui/platforms/standalone/* | \
        CMakeLists.txt | \
        scripts/build-* | \
        packaging/*) has_standalone=1 ;;

        # Plasma-only: the Plasma adapters, the top-level Plasma host
        # wrappers (main.qml + the config*.qml dialog shells), and the
        # KConfig schema. The standalone build loads none of these.
        contents/ui/platforms/plasma/* | \
        contents/ui/*.qml | \
        contents/config/*) has_plasma=1 ;;

        # Everything else (docs/, tests/, .github/, README.md, the root
        # CLAUDE.md, metadata.json) is neutral: it doesn't bind the
        # release to one platform.
        *) : ;;
    esac
done

if [ "$has_core" -eq 1 ]; then
    printf ''
elif [ "$has_plasma" -eq 1 ] && [ "$has_standalone" -eq 0 ]; then
    printf -- '-p'
elif [ "$has_standalone" -eq 1 ] && [ "$has_plasma" -eq 0 ]; then
    printf -- '-s'
else
    printf ''
fi
