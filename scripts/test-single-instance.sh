#!/usr/bin/env bash
# Live verification of the standalone single-instance IPC (issues #103/#104).
#
# Why this exists: the version-mismatch takeover path ("open a different build
# over a running one → the old quits, the new takes over") can't be exercised
# inside the sandboxed agent environment (it reaps detached GUI processes), so
# this script lets a human run it on a real session. It covers the two halves:
#
#   default (fast, no rebuild) — PROTOCOL probe against a running primary:
#     • same-version  "show <v>"        → reply "defer",    primary stays
#     • unknown intent "garbage zzz"     → reply "defer",    primary stays
#     • open-settings "open-settings <v>"→ reply "defer",    primary stays
#     • DIFFERENT-version "show 9.9.9"   → reply "takeover",  primary QUITS
#
#   --full — round-trip with a SECOND, differently-versioned binary:
#     builds ring-monitor-standalone with RING_MONITOR_VERSION=9.9.9-test into
#     a throwaway build dir, launches the normal build as primary, then launches
#     the 9.9.9 build → asserts the primary process exits and the newcomer ends
#     up the sole socket owner. This is the real "newer AppImage replaces the
#     running one" scenario.
#
# Usage:
#   scripts/test-single-instance.sh           # fast protocol probe
#   scripts/test-single-instance.sh --full    # + two-version round-trip
#
# Run from the repo root. Needs python3 and a configured build/ dir (the script
# builds the main binary if missing). The --full path needs cmake + the same Qt
# toolchain a normal build uses.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

BIN="$REPO/build/ring-monitor-standalone"
SOCK_NAME="dev.manuacl.ring-monitor"
PASS=0
FAIL=0

note()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m  PASS\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
bad()   { printf '\033[1;31m  FAIL\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }

# Resolve the QLocalServer socket path. Qt puts it under the temp dir; discover
# it rather than hardcode (it differs by $TMPDIR / $XDG_RUNTIME_DIR).
find_socket() {
    local s
    for s in "${XDG_RUNTIME_DIR:-}/$SOCK_NAME" "${TMPDIR:-/tmp}/$SOCK_NAME" "/tmp/$SOCK_NAME"; do
        [ -n "$s" ] && [ -S "$s" ] && { echo "$s"; return 0; }
    done
    # Fall back to a filesystem search of the usual locations.
    find "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" "${TMPDIR:-/tmp}" /tmp \
        -maxdepth 2 -name "$SOCK_NAME" -type s 2>/dev/null | head -1
}

# Listener count for the socket name (a live primary == 1).
listeners() { ss -lx 2>/dev/null | grep -c "$SOCK_NAME"; }

# Send "<msg>" to the socket, print the trimmed reply (empty on no-reply).
probe() {
    local sock="$1" msg="$2"
    python3 - "$sock" "$msg" <<'PY'
import socket, sys
sock, msg = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.settimeout(3)
try:
    s.connect(sock); s.sendall(msg.encode())
    print(s.recv(64).decode(errors="replace").strip())
except Exception as e:
    print(f"<error: {e}>", file=sys.stderr)
finally:
    s.close()
PY
}

cleanup_pid() { [ -n "${1:-}" ] && kill -TERM "$1" 2>/dev/null; }

# ── Ensure the main binary exists ───────────────────────────────────────────
if [ ! -x "$BIN" ]; then
    note "build/ binary missing — configuring + building (capped -j2)"
    cmake -S "$REPO" -B "$REPO/build" >/dev/null || { echo "configure failed"; exit 2; }
    cmake --build "$REPO/build" --parallel 2 >/dev/null || { echo "build failed"; exit 2; }
fi
LOCAL_VER="$(grep -o '"Version"[[:space:]]*:[[:space:]]*"[^"]*"' metadata.json | grep -o '[0-9][^"]*')"
note "main build version = $LOCAL_VER"

# ── Phase 1: protocol probe (no rebuild) ────────────────────────────────────
note "Phase 1: launching primary + probing the four verdicts"
# A pre-existing widget (e.g. your real desktop instance) owns the socket and
# would make every assertion ambiguous — our launched test-primary would defer
# to it, and the global listener count can't tell the two apart. Refuse rather
# than rm its socket out from under it.
if [ "$(listeners)" -ge 1 ]; then
    bad "a ring-monitor-standalone is ALREADY running (your desktop widget?) — close it first (pkill -f ring-monitor-standalone), then re-run"
    echo; echo "Result: $PASS passed, $FAIL failed"; exit 1
fi
# Launch directly (no setsid) so $! is the real binary PID — every assertion
# below checks THIS process, not a global count.
"$BIN" </dev/null >/tmp/rm-si-primary.log 2>&1 &
PRIMARY=$!
sleep 3
SOCK="$(find_socket)"
if ! kill -0 "$PRIMARY" 2>/dev/null || [ -z "$SOCK" ]; then
    bad "primary (pid $PRIMARY) did not come up / socket not found — cannot probe"
    cleanup_pid "$PRIMARY"
    echo; echo "Result: $PASS passed, $FAIL failed"; exit 1
fi
note "primary pid=$PRIMARY  socket=$SOCK"

# alive_after "<label>": assert the launched primary is STILL running.
alive_after() { kill -0 "$PRIMARY" 2>/dev/null && ok "primary still running after $1" || bad "primary (pid $PRIMARY) exited after $1"; }

r="$(probe "$SOCK" "show ${LOCAL_VER}"$'\n')"
[ "$r" = "defer" ] && ok "same-version show → defer" || bad "same-version show → '$r' (expected defer)"
alive_after "same-version show"

r="$(probe "$SOCK" $'garbage zzz\n')"
[ "$r" = "defer" ] && ok "unknown intent → defer" || bad "unknown intent → '$r' (expected defer)"
alive_after "unknown intent (must never quit)"

r="$(probe "$SOCK" "open-settings ${LOCAL_VER}"$'\n')"
[ "$r" = "defer" ] && ok "open-settings → defer" || bad "open-settings → '$r' (expected defer)"
alive_after "open-settings"

r="$(probe "$SOCK" $'show 9.9.9\n')"
[ "$r" = "takeover" ] && ok "different-version show → takeover" || bad "different-version show → '$r' (expected takeover)"
sleep 2
# The takeover path emits supersededRequested → Qt.quit, so THIS pid must exit.
kill -0 "$PRIMARY" 2>/dev/null && bad "primary (pid $PRIMARY) still alive after takeover (should have quit)" \
                                || ok "primary (pid $PRIMARY) quit after takeover"

cleanup_pid "$PRIMARY"; sleep 1
rm -f "$SOCK" 2>/dev/null

# ── Phase 2 (optional): two-version round-trip ──────────────────────────────
if [ "${1:-}" = "--full" ]; then
    note "Phase 2 (--full): building a 9.9.9-test binary for a real round-trip"
    BDIR="$REPO/build-vtest"
    # The version comes from metadata.json (CMake set() overrides any -D), so
    # temporarily swap it, configure+build the second binary, then restore.
    cp metadata.json /tmp/rm-meta-backup.json
    sed -i 's/"Version"[[:space:]]*:[[:space:]]*"[^"]*"/"Version": "9.9.9-test"/' metadata.json
    cmake -S "$REPO" -B "$BDIR" >/dev/null && cmake --build "$BDIR" --parallel 2 >/dev/null
    rc=$?
    cp /tmp/rm-meta-backup.json metadata.json   # restore BEFORE asserting
    if [ $rc -ne 0 ]; then
        bad "second-version build failed — skipping round-trip"
    else
        BIN2="$BDIR/ring-monitor-standalone"
        # Launch directly (no setsid) so $! is the real binary PID.
        "$BIN" </dev/null >/tmp/rm-si-primary.log 2>&1 &
        P1=$!
        sleep 3
        if ! kill -0 "$P1" 2>/dev/null; then
            bad "primary ($LOCAL_VER, pid $P1) did not come up for round-trip"
        else
            note "primary $LOCAL_VER up (pid $P1); launching 9.9.9-test over it"
            "$BIN2" </dev/null >/tmp/rm-si-newcomer.log 2>&1 &
            P2=$!
            sleep 4
            kill -0 "$P1" 2>/dev/null && bad "old primary ($LOCAL_VER, pid $P1) still alive (should have been superseded)" \
                                       || ok "old primary ($LOCAL_VER) exited on takeover"
            kill -0 "$P2" 2>/dev/null && [ "$(listeners)" -ge 1 ] \
                && ok "newcomer (9.9.9-test, pid $P2) is the live widget + socket owner" \
                || bad "newcomer (9.9.9-test, pid $P2) is not the live primary"
            cleanup_pid "$P2"
        fi
        cleanup_pid "$P1"; sleep 1
        rm -f "$(find_socket)" 2>/dev/null
    fi
    rm -rf "$BDIR"
fi

echo
note "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
