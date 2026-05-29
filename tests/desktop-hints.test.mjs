// Text-level guards for the standalone EWMH-hints C++ file.
// `standalone/desktop_hints.cpp` links xcb at C++ level and can't be
// loaded by qmltestrunner-qt6 or driven from a Node unit test. The
// same text-guard pattern as `autostart.test.mjs`, `standalone-main.test.mjs`,
// and `standalone-metrics-backend.test.mjs`.
//
// The contract these guards lock in:
//
//   1. `_NET_WM_STATE` is declared as a PROPERTY (via `xcb_change_property`)
//      before the window maps, NOT via a ClientMessage. The
//      ClientMessage form (`xcb_send_event` + `XCB_CLIENT_MESSAGE`)
//      is the EWMH-spec'd path for changing the state of a MAPPED
//      window at runtime. Our caller runs pre-`app.exec()`, so the
//      QML `visible: true` show() hasn't yet been processed → the
//      window is unmapped → KWin / mutter silently drop the
//      ClientMessages and STICKY / SKIP_* show up flaky in `xprop`.
//      Property writes are read by the WM during `MapRequest`,
//      which is the spec-compliant pre-map declaration path.
//
//   2. The state list explicitly includes `_NET_WM_STATE_BELOW`. Qt
//      adds it post-map via its own ClientMessage (driven by
//      `Qt::WindowStaysOnBottomHint`), but our `XCB_PROP_MODE_REPLACE`
//      pre-map would otherwise clobber it. Being explicit removes the
//      race with Qt's xcb-plugin init order.
//
//   3. XWayland probe is still in place (regression guard).
//
//   4. No Plasma headers — standalone isolation invariant.

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SRC = readFileSync(
    join(__dirname, "..", "standalone", "desktop_hints.cpp"),
    "utf8",
);
const HEADER = readFileSync(
    join(__dirname, "..", "standalone", "desktop_hints.h"),
    "utf8",
);

test("_NET_WM_STATE is declared via xcb_change_property, not xcb_send_event", () => {
    // The whole point of the fix: ClientMessages on an unmapped
    // window get dropped by KWin/mutter. The function must emit a
    // single property write with the state list.
    assert.match(
        SRC,
        /xcb_change_property\([^)]*net_wm_state[\s\S]*?XCB_ATOM_ATOM/,
        "net_wm_state must be set as a property (XCB_ATOM_ATOM) via xcb_change_property",
    );
    assert.doesNotMatch(
        SRC,
        /xcb_send_event/,
        "must NOT call xcb_send_event — ClientMessages on unmapped windows are dropped by KWin/mutter (review finding 🔴 PR #27)",
    );
    assert.doesNotMatch(
        SRC,
        /XCB_CLIENT_MESSAGE|xcb_client_message_event_t/,
        "must NOT use ClientMessage event types — the property write replaces them",
    );
});

test("state list includes _NET_WM_STATE_BELOW explicitly", () => {
    // Qt adds BELOW post-map via Qt::WindowStaysOnBottomHint, but our
    // XCB_PROP_MODE_REPLACE pre-map would clobber it. The explicit
    // include removes the race with Qt's xcb-plugin init.
    assert.match(
        SRC,
        /internAtom\([^)]*"_NET_WM_STATE_BELOW"/,
        "must intern _NET_WM_STATE_BELOW",
    );
    assert.match(
        SRC,
        /states\[\]\s*=\s*\{[^}]*state_below[^}]*\}/,
        "the states array must include state_below alongside sticky / skip_taskbar / skip_pager",
    );
});

test("SCENARIO desktop-click vanish: window type is NORMAL, not DESKTOP", () => {
    // The widget used to set `_NET_WM_WINDOW_TYPE_DESKTOP`, which put it
    // in plasmashell's own containment layer: a left-click on the
    // desktop raised the opaque wallpaper containment over it and the
    // widget vanished (process alive, window occluded — not a crash).
    // `NORMAL` + the `BELOW` state pins it one layer above the
    // wallpaper, surviving a desktop click on every EWMH stacking WM we
    // target (KWin, mutter, xfwm4). The type must still be REPLACEd (not
    // omitted) to clear the `_KDE_NET_WM_WINDOW_TYPE_OVERRIDE` that
    // `Qt::FramelessWindowHint` sets, which would otherwise leave the
    // window override-redirect / partially unmanaged.
    assert.match(
        SRC,
        /internAtom\([^)]*"_NET_WM_WINDOW_TYPE_NORMAL"/,
        "must intern _NET_WM_WINDOW_TYPE_NORMAL",
    );
    assert.match(
        SRC,
        /xcb_change_property\([^)]*net_wm_window_type[\s\S]*?window_type_normal/,
        "must REPLACE _NET_WM_WINDOW_TYPE with the NORMAL atom (clears the OVERRIDE side-effect of FramelessWindowHint)",
    );
    assert.doesNotMatch(
        SRC,
        /_NET_WM_WINDOW_TYPE_DESKTOP/,
        "must NOT use _NET_WM_WINDOW_TYPE_DESKTOP — it collides with plasmashell's containment and vanishes on desktop-click",
    );
});

test("forceXWaylandUnderWayland probes for Xwayland before forcing xcb", () => {
    // Regression guard for the earlier 🟠 fix (PR #27 → fixed in PR #35):
    // on Plasma-Wayland with `xorg-x11-server-Xwayland` removed,
    // `QT_QPA_PLATFORM=xcb` causes the xcb plugin to fail to load and
    // the binary aborts at startup. The probe makes the fallback
    // silent-but-running (EWMH hints no-op off X11).
    assert.match(
        SRC,
        /QStandardPaths::findExecutable\(\s*QStringLiteral\(\s*"Xwayland"\s*\)\s*\)/,
        "must probe Xwayland via QStandardPaths::findExecutable before qputenv",
    );
});

test("desktop_hints includes no Plasma headers (standalone isolation)", () => {
    assert.doesNotMatch(
        SRC,
        /#include\s*<plasma\//,
        "desktop_hints.cpp must not include Plasma headers",
    );
    assert.doesNotMatch(
        HEADER,
        /#include\s*<plasma\//,
        "desktop_hints.h must not include Plasma headers",
    );
});

test("forceXWaylandUnderWayland warns when Xwayland is missing", () => {
    // Review finding 🟠 PR #27: without a diagnostic line the silent
    // fallback to native Wayland (where applyDesktopWindowHints no-ops)
    // leaves the user with an un-hinted floating window and no clue why.
    // The warning must mention Xwayland and the EWMH hint family so it's
    // greppable in the journal.
    assert.match(
        SRC,
        /qWarning\([^)]*Xwayland[\s\S]*?_NET_WM_/,
        "must qWarning when Xwayland is missing, naming the EWMH hint family",
    );
});

test("applyDesktopWindowHints warns when X11 native interface is unavailable", () => {
    // Same review finding 🟠 PR #27: the second silent-no-op branch
    // is when nativeInterface<QX11Application>() returns nullptr
    // (running on native Wayland after the XWayland probe declined to
    // force xcb, or on a non-X11 platform). Emit a warning so the
    // unset hints are debuggable.
    assert.match(
        SRC,
        /if\s*\(\s*!x11\s*\)\s*\{[\s\S]*?qWarning\([^)]*native Wayland/,
        "must qWarning when the X11 native interface is unavailable",
    );
});

test("applyDesktopWindowHints header documents the pre-map requirement", () => {
    // The function only works PRE-MAP — it uses xcb_change_property,
    // which the WM reads at MapRequest. Calling it after the window
    // is mapped silently fails (property updates, but KWin/mutter
    // don't re-read state post-map). A future caller adding a
    // "reapply hints on theme switch" path without reading the cpp
    // would silently break STICKY/SKIP_TASKBAR/SKIP_PAGER again.
    // The header must spell out the contract above the declaration.
    assert.match(
        HEADER,
        /PRE-MAP[\s\S]*?applyDesktopWindowHints/,
        "header must mention PRE-MAP requirement above the declaration",
    );
    assert.match(
        HEADER,
        /BEFORE\s+`?app\.exec\(\)`?|before.*MapWindow|before.*MapRequest/,
        "header must explain WHEN to call it (before app.exec / MapWindow / MapRequest)",
    );
});

test("applyDesktopWindowHints asserts the pre-map invariant in debug builds", () => {
    // Q_ASSERT(!window->isExposed()) catches a future post-map caller
    // loudly in debug builds. Release builds no-op the assert but
    // still get the property write — wrong WM state, but no crash.
    assert.match(
        SRC,
        /Q_ASSERT\(\s*!window->isExposed\(\)\s*\)/,
        "must Q_ASSERT(!window->isExposed()) as the pre-map invariant guard",
    );
});

test("xcb_intern_atom length is explicitly cast to uint16_t", () => {
    // Cosmetic but matters under -Wconversion: qstrlen returns uint,
    // xcb_intern_atom takes uint16_t. Implicit narrowing trips clang
    // warnings on builds with stricter flags.
    assert.match(
        SRC,
        /xcb_intern_atom\([^)]*static_cast<uint16_t>\(\s*qstrlen/,
        "xcb_intern_atom length must be wrapped in static_cast<uint16_t> to silence -Wconversion",
    );
});
