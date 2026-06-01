// Text-level guards for the standalone single-instance guard + wake-up IPC
// (issues #103 / #104). The C++ (`standalone/single_instance.{h,cpp}`) links
// Qt Network and can't be loaded by qmltestrunner-qt6 or a Node unit test, and
// `main.cpp` decides the client-probe-vs-server path before any QML loads — so
// the contract is asserted as source text, the same pattern as
// `nvml-reader.test.mjs`, `desktop-hints.test.mjs`, and `standalone-main-cpp.test.mjs`.
//
// The contract these guards lock in:
//
//   1. Race-safe claim: tryListen() listens FIRST and only clears a socket it
//      has proven stale (re-probe) — it never blindly removeServer()s a live
//      primary's socket. A live owner during the race → Claim::Busy.
//   2. Version-aware verdict: open-settings (any version) / same-version show /
//      unknown intent → reply "defer" (newcomer exits, widget never quits on an
//      unknown intent); a different-version show → reply "takeover" then
//      supersededRequested + close the server so the newcomer can claim it.
//   3. One newline-terminated frame per connection ("<intent> <version>\n");
//      both ends read up to the '\n' so a split delivery can't truncate the
//      version or the reply (finding F1). Wire tokens are shared constants
//      (SingleInstanceProtocol::*), not duplicated bare literals.
//   4. main.cpp runs a bounded probe-then-act loop, acts only on an explicit
//      reply (never a timeout), claims via tryListen, and exposes the guard to
//      QML as the SingleInstance context property (NOT a module-URI singleton,
//      which would clobber the module's auto-registered C++ elements).
//   5. Main.qml shows its in-process dialog on openSettingsRequested (#104) and
//      quits on supersededRequested (lets a different build take over).
//   6. CMake links Qt6::Network and compiles single_instance.cpp.

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const read = (...p) => readFileSync(join(__dirname, "..", ...p), "utf8");

const HEADER = read("standalone", "single_instance.h");
const SRC = read("standalone", "single_instance.cpp");
const MAIN = read("standalone", "main.cpp");
const MAIN_QML = read("contents", "ui", "platforms", "standalone", "Main.qml");
const CMAKE = read("CMakeLists.txt");

test("single_instance uses QLocalServer + QLocalSocket", () => {
    assert.match(SRC, /QLocalServer/, "must use QLocalServer for the primary");
    assert.match(SRC, /QLocalSocket/, "must accept QLocalSocket client connections");
});

test("tryListen is race-safe: listen FIRST, only clear a proven-stale socket", () => {
    // Review finding #1: it must NOT blindly removeServer() before listen(), or a
    // second launch racing a live primary would unlink the live socket. It tries
    // listen() first; only on AddressInUseError does it re-probe, and only
    // removeServer() when no live owner answers.
    assert.match(
        SRC,
        /listen\([\s\S]*?AddressInUseError[\s\S]*?connectToServer\([\s\S]*?removeServer\(/,
        "tryListen must listen first, then re-probe on AddressInUseError before removeServer",
    );
    assert.match(SRC, /Claim::Busy/, "must return Busy when a live owner won the race");
    assert.match(SRC, /Claim::Acquired/, "must return Acquired on a successful listen");
});

test("single_instance declares the three intent signals", () => {
    assert.match(HEADER, /void\s+openSettingsRequested\(\)/, "must declare openSettingsRequested()");
    assert.match(HEADER, /void\s+showRequested\(\)/, "must declare showRequested()");
    assert.match(HEADER, /void\s+supersededRequested\(\)/, "must declare supersededRequested()");
});

test("single_instance reads the whole framed line before parsing (no truncation)", () => {
    // Finding F1: the message is one newline-terminated line "<intent> <version>\n",
    // so reading up to the first '\n' proves the WHOLE line (intent AND version)
    // arrived — a split delivery can't truncate the version. Keep reading until
    // that delimiter is present.
    assert.match(
        SRC,
        /while\s*\(\s*!payload\.contains\('\\n'\)[\s\S]*?waitForReadyRead/,
        "must loop reading until the newline frame delimiter is present",
    );
    // Parse the version from after the first space, before the newline.
    assert.match(SRC, /line\.indexOf\(' '\)/, "must split intent/version on the space within the framed line");
});

test("single_instance only supersedes a DIFFERENT-version show; unknown intent never quits", () => {
    // Review finding #3: supersede is gated on intent==show AND a non-empty
    // version that differs — NOT a catch-all else. An unknown/garbled intent
    // must fall to the defer path, never emit supersededRequested.
    assert.match(
        SRC,
        /intent\s*==\s*kIntentShow\s*&&\s*!version\.isEmpty\(\)\s*&&\s*version\s*!=\s*m_localVersion/,
        "supersede must require a show intent with a non-empty differing version",
    );
    assert.match(
        SRC,
        /==\s*kIntentOpenSettings[\s\S]*?openSettingsRequested\(\)/,
        "the open-settings message must emit openSettingsRequested()",
    );
    // Same-version relaunch keeps showing: it does NOT meet the supersede gate
    // (version != m_localVersion is false), so it falls to the defer/showRequested
    // branch — never quits.
    assert.match(SRC, /version\s*!=\s*m_localVersion/, "supersede is gated on a DIFFERING version (same version → no quit)");
});

test("single_instance replies takeover then closes its server; defer otherwise", () => {
    // Takeover: reply BEFORE quitting so the newcomer reliably reads it, then
    // close the server synchronously so the socket frees before its tryListen().
    assert.match(
        SRC,
        /reply\(kReplyTakeover\)[\s\S]*?supersededRequested\(\)[\s\S]*?m_server->close\(\)/,
        "must reply takeover, emit supersededRequested, then close the server",
    );
    assert.match(SRC, /reply\(kReplyDefer\)/, "must reply defer so a deferring newcomer exits");
});

test("the wire protocol tokens are shared constants (no duplicated bare literals)", () => {
    // Both ends use SingleInstanceProtocol::* so a typo can't silently break the
    // handshake. The tokens are declared once in the header.
    assert.match(HEADER, /namespace SingleInstanceProtocol/, "must declare the shared protocol namespace");
    assert.match(HEADER, /kReplyTakeover\b/, "must define the takeover reply token");
    assert.match(HEADER, /kIntentShow\b/, "must define the show intent token");
    assert.match(MAIN, /SingleInstanceProtocol|kReply|kIntent/, "main.cpp must use the shared protocol tokens, not bare literals");
});

test("single_instance is NOT a QML_ELEMENT (exposed as a context property)", () => {
    // The instance QML connects to must be the one that called listen(), so the
    // engine must not lazily construct its own. Anchor on the macro-on-its-own-
    // line form, not a bare /QML_ELEMENT/ — the header comment explains *why*
    // it's not one (tests/CLAUDE.md "doesNotMatch targets the call").
    assert.doesNotMatch(HEADER, /^\s*QML_ELEMENT\s*$/m, "must not auto-register as a QML element");
});

test("main.cpp loops probe→act, reads the whole reply, exits unless told 'takeover'", () => {
    assert.match(MAIN, /connectToServer\(/, "must probe via QLocalSocket::connectToServer");
    assert.match(MAIN, /waitForConnected\(/, "must wait (bounded) for the probe to connect");
    // Sends "<intent> <version>\n" built from the shared protocol tokens.
    assert.match(
        MAIN,
        /kIntentOpenSettings[\s\S]*?kIntentShow[\s\S]*?localVersion\.toUtf8\(\)\s*\+\s*'\\n'/,
        "must send <intent> <version>\\n built from the shared tokens + local version",
    );
    // Mirror the server's framed read so a split "takeover\n" isn't misread.
    assert.match(
        MAIN,
        /while\s*\(\s*!reply\.contains\('\\n'\)[\s\S]*?waitForReadyRead/,
        "must read the reply until the newline frame delimiter",
    );
    // Only an explicit takeover makes the newcomer claim the socket; anything
    // else (defer / unknown / no reply) exits — never hijack on a timeout
    // (review findings #1/#2).
    assert.match(
        MAIN,
        /reply\s*==\s*kReplyTakeover[\s\S]*?waitForDisconnected\([\s\S]*?continue;/,
        "takeover must wait for disconnect then loop to claim the socket",
    );
    assert.match(MAIN, /return 0;/, "a non-takeover reply must exit");
});

test("main.cpp uses race-safe tryListen, defers on Busy, exposes the guard to QML", () => {
    // openSettings recovery must not claim the socket (it would block a later
    // widget launch); the start-up race loser (Busy) re-probes and defers.
    assert.match(
        MAIN,
        /if\s*\(\s*openSettings\s*\)\s*\n?\s*break;/,
        "the --open-settings recovery path must not claim the socket",
    );
    assert.match(MAIN, /singleInstance\.tryListen\(/, "must claim via the race-safe tryListen()");
    assert.match(
        MAIN,
        /Claim::Busy[\s\S]*?continue;/,
        "a Busy result (lost the race) must loop and defer to the winner",
    );
    // Exposed as a CONTEXT PROPERTY, not qmlRegisterSingletonInstance into the
    // module URI: registering a type into the qt_add_qml_module-owned
    // "RingMonitor.Standalone" clobbers its auto-registered C++ elements
    // (ProcReader/NvmlReader) → the root fails to load with "ProcReader is not a
    // type" and the binary exits 1 (caught by the offscreen smoke test).
    assert.match(
        MAIN,
        /setContextProperty\(\s*"SingleInstance"\s*,\s*&singleInstance\s*\)/,
        "the guard must be exposed as the SingleInstance context property",
    );
    assert.doesNotMatch(
        MAIN,
        /qmlRegisterSingletonInstance\([^)]*SingleInstance/,
        "must NOT register into the module URI (clobbers ProcReader/NvmlReader → load fails)",
    );
});

test("main.cpp warns when it runs without securing the socket", () => {
    // Review finding #5: a degraded main-widget launch (listen failed / lost the
    // race every attempt) runs anyway but must leave a trace.
    assert.match(
        MAIN,
        /!openSettings\s*&&\s*!becamePrimary[\s\S]*?qWarning/,
        "must qWarning when the main widget did not acquire the socket",
    );
});

test("Main.qml reacts to openSettings (show dialog) and supersede (quit)", () => {
    assert.match(
        MAIN_QML,
        /target:\s*SingleInstance[\s\S]*?function onOpenSettingsRequested\(\)\s*\{[\s\S]*?settingsDialog\.show\(\)/,
        "Main.qml must connect SingleInstance.openSettingsRequested → settingsDialog.show()",
    );
    assert.match(
        MAIN_QML,
        /function onSupersededRequested\(\)\s*\{[\s\S]*?Qt\.quit\(\)/,
        "Main.qml must quit on SingleInstance.supersededRequested (lets a new build take over)",
    );
});

test("CMake links Qt6::Network and compiles single_instance.cpp", () => {
    assert.match(
        CMAKE,
        /find_package\(Qt6[^)]*\bNetwork\b/,
        "find_package(Qt6 ...) must request the Network component",
    );
    assert.match(CMAKE, /Qt6::Network/, "must link Qt6::Network");
    assert.match(CMAKE, /standalone\/single_instance\.cpp/, "must compile single_instance.cpp");
});
