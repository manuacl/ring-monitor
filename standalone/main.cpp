// Standalone entry point for ring-monitor.
//
// Counterpart to the Plasma host (contents/ui/main.qml + the
// plasmoid metadata in metadata.json). When this binary runs, it
// creates a QGuiApplication and loads the QML root from the
// RingMonitor.Standalone module — which qt_add_qml_module in
// CMakeLists.txt registered at build time.
//
// Compositor integration (Conky-style desktop widget — sticky,
// below, no taskbar, no pager) lives in `desktop_hints.{h,cpp}`, which
// also picks the window strategy (`decideWindowStrategy`): X11 / Wayland
// -GNOME use the EWMH-over-XWayland path; wlroots / KWin Wayland use a
// native wlr-layer-shell bottom-layer surface (standalone/wayland_layer_shell.*,
// only when layer-shell-qt is compiled in). See
// `docs/plasma-isolation/plan.md` "Window model" and
// `contents/ui/platforms/standalone/CLAUDE.md`.

#include "autostart.h"
#include "desktop_hints.h"
#include "menu_entry.h"
#include "single_instance.h"

#include <QGuiApplication>
#include <QLocalSocket>
#include <QQmlApplicationEngine>
#include <QString>
#include <QWindow>
#include <QtQml>

// Injected by CMake from metadata.json (KPlugin.Version) — the
// single source of truth the release pipeline bumps. The fallback
// only fires for a non-CMake build (none exists today); the
// `-dev` suffix makes such a build self-identify.
#ifndef RING_MONITOR_VERSION
#define RING_MONITOR_VERSION "0.0.0-dev"
#endif

int main(int argc, char *argv[])
{
    // Argv parse before QGuiApplication: --open-settings switches
    // the QML root that's loaded, which must be decided before
    // engine.loadFromModule. Argv parsing happens here (not via
    // QCommandLineParser) because the flag also gates
    // `forceXWaylandUnderWayland`, which mutates QT_QPA_PLATFORM
    // and must therefore run BEFORE QGuiApplication is constructed
    // (Qt reads QT_QPA_PLATFORM at app init); QCommandLineParser
    // requires a constructed QCoreApplication.
    //
    // --open-settings: load `SettingsOnlyRoot` instead of `Main`.
    // Recovery path for the case where the compositor swallows the
    // right-click on the wallpaper-layer widget window (some KWin /
    // mutter setups route desktop-area clicks to the containment) —
    // without this flag the user would have to
    // `pkill ring-monitor-standalone` and re-edit
    // ~/.config/dev.manuacl/ring-monitor.conf by hand.
    //
    // SettingsOnlyRoot.qml hosts only the dialog (ConfigStore +
    // Theme + UpdateChecker + SettingsDialog); the rings widget is
    // not constructed at all. See its file docblock for why this
    // shape beats threading a `_settingsOnly` flag through Main.qml.
    //
    // Implementation note: `--open-settings` is the RECOVERY path, used
    // only when no widget is running (or a wedged one didn't answer the
    // single-instance probe below). When a widget IS running, the probe
    // routes the request to it via IPC and this process exits before
    // loading any root — so the dialog opens IN-PROCESS in the running
    // widget, where its writes go through the same ConfigStore the rings
    // read and therefore apply live (issues #103 / #104, see
    // single_instance.h). The separate-process recovery root below only
    // loads when there's nothing to route to.
    bool openSettings = false;
    for (int i = 1; i < argc; ++i) {
        const QString arg = QString::fromLocal8Bit(argv[i]);
        if (arg == QLatin1String("--open-settings") ||
            arg == QLatin1String("--settings")) {
            openSettings = true;
        }
    }

    // Pick the window strategy once. Only X11Ewmh needs pre-QGuiApplication
    // setup — the QT_QPA_PLATFORM=xcb force for Wayland-GNOME, which Qt
    // reads at platform init.
    //
    // WaylandLayerShell does NOT call the global LayerShellQt::Shell::
    // useLayerShell() on purpose: that sets QT_WAYLAND_SHELL_INTEGRATION
    // process-wide, turning EVERY window — including the right-click
    // context menu's popup and the settings dialog — into a full-output
    // layer surface (fullscreen, un-dismissable). Instead the layer role
    // is opted into PER WINDOW via LayerShellQt::Window::get() in
    // WaylandLayerShell::configure() (Main.qml's _anchor()), so only the
    // rings window is a layer surface and popups/dialogs stay normal
    // xdg-shell windows. Qt's Wayland plugin supports this per-window
    // selection since 6.5 (which is why useLayerShell() is deprecated).
    //
    // Floating (recovery) is a normal managed window — nothing to force.
    const ringmonitor::WindowStrategy strategy =
        ringmonitor::decideWindowStrategy(openSettings);
    if (strategy == ringmonitor::WindowStrategy::X11Ewmh)
        ringmonitor::forceXWaylandUnderWayland();

    QGuiApplication app(argc, argv);

    // Standard Qt application identity. Qt.labs.settings uses these
    // to compute the config file path
    // (~/.config/dev.manuacl/ring-monitor.conf).
    QGuiApplication::setOrganizationName("dev.manuacl");
    QGuiApplication::setApplicationName("ring-monitor");
    QGuiApplication::setApplicationVersion(QStringLiteral(RING_MONITOR_VERSION));
    // Tie the running app to its installed desktop entry. Under Wayland
    // this sets the surface app_id, so the compositor maps the window
    // to packaging/dev.manuacl.ringmonitor.desktop (correct icon +
    // taskbar grouping). No-op when the entry isn't installed (a
    // build-from-source run), so it's harmless outside the AppImage.
    QGuiApplication::setDesktopFileName("dev.manuacl.ringmonitor");

    // ── Single-instance guard + wake-up IPC (issues #103 / #104) ──────
    // Probe-then-act loop. Each pass: if a primary is listening, hand it our
    // intent + version and obey its explicit reply; otherwise try to become the
    // primary. The newcomer NEVER acts on a timeout — only on an explicit reply
    // — so a busy/wedged primary is never hijacked (review findings #1/#2):
    //   • reply "defer"   → exit WITHOUT loading a QML root. Any --open-settings
    //     (it opened its in-process dialog → live config, #104) and a same-version
    //     relaunch (no pile-up, #103).
    //   • reply "takeover" → a different-version primary is quitting; wait for it
    //     to release the socket, then loop and claim it.
    //   • no reply        → a primary is there but unresponsive; exit rather than
    //     stealing its socket (kill it manually to replace a wedged one).
    // tryListen() is itself race-safe: it listens first and only clears a socket
    // it has PROVEN stale (re-probe), so two simultaneous launches can't both
    // become primary — the loser gets Busy and re-probes into the defer path.
    // The socket name is fixed and per-user ($XDG_RUNTIME_DIR-scoped by Qt).
    const QString instanceSocket = QStringLiteral("dev.manuacl.ring-monitor");
    const QString localVersion = QStringLiteral(RING_MONITOR_VERSION);
    SingleInstance singleInstance(localVersion);
    bool becamePrimary = false;
    for (int attempt = 0; attempt < 5 && !becamePrimary; ++attempt) {
        QLocalSocket probe;
        probe.connectToServer(instanceSocket);
        if (probe.waitForConnected(100)) {
            // One newline-terminated line "<intent> <version>\n" — the '\n' is
            // the frame delimiter, so the server reading up to it gets the whole
            // message (intent AND version), never a truncated version (F1). Wire
            // tokens are the shared SingleInstanceProtocol constants so a typo on
            // one side can't silently break the handshake.
            using namespace SingleInstanceProtocol;
            const QByteArray hello =
                (openSettings ? QByteArray(kIntentOpenSettings) : QByteArray(kIntentShow))
                + ' ' + localVersion.toUtf8() + '\n';
            probe.write(hello);
            probe.waitForBytesWritten(100);
            // Read the whole reply line, mirroring the server's framing: a split
            // "takeover\n" must not be misread as non-takeover, which would make
            // BOTH this process and the quitting primary exit, leaving no widget.
            QByteArray reply;
            while (!reply.contains('\n') && probe.waitForReadyRead(2000))
                reply += probe.readAll();
            reply = reply.left(reply.indexOf('\n')).trimmed();
            if (reply == kReplyTakeover) {
                probe.waitForDisconnected(2500);
                continue;  // primary is quitting → loop and claim the socket
            }
            return 0;  // "defer" / unknown / no reply → a primary handled us
        }
        // No primary listening. The --open-settings recovery editor must NOT
        // claim the socket (it's transient and would block a later widget launch).
        if (openSettings)
            break;
        const SingleInstance::Claim claim = singleInstance.tryListen(instanceSocket);
        if (claim == SingleInstance::Claim::Acquired)
            becamePrimary = true;
        else if (claim == SingleInstance::Claim::Busy)
            continue;  // lost the start-up race → re-probe and defer to the winner
        else
            break;  // Failed (non-recoverable) → run anyway, unguarded
    }
    // Degraded: we're the main widget but never secured the socket (listen()
    // failed, or we lost the start-up race every attempt). Run anyway — a
    // visible widget beats refusing to start — but leave a trace, since a later
    // launch won't see us and could stack a second window.
    if (!openSettings && !becamePrimary)
        qWarning("ring-monitor: single-instance socket not acquired; running unguarded");

    // Self-heal stale launcher Exec= paths on EVERY normal startup, not only
    // when the Settings dialog instantiates these helpers (#126). After an
    // AppImage update the versioned filename changes, so a previously written
    // autostart / menu entry points at the old binary; the next login (or
    // menu launch) would run the stale version. Each ctor calls
    // desktop_entry::refreshIfStale, which rewrites the entry to the current
    // $APPIMAGE — a no-op when the entry is absent, already current, or we're
    // a fixed-path dev build. The entry tracks whichever binary actually runs
    // as the widget: the single-instance handshake makes a just-launched
    // *different-version* process take over and become primary (so an update
    // re-points the launchers), and that primary is what reaches here.
    // Skipped in --open-settings recovery — that process is the deliberately
    // non-authoritative config editor (it never claims the single-instance
    // socket), so it must not rewrite the user's launchers either.
    if (!openSettings) {
        [[maybe_unused]] Autostart autostartRefresh;
        [[maybe_unused]] MenuEntry menuEntryRefresh;
    }

    QQmlApplicationEngine engine;
    // Expose the guard to QML as a context property — NOT
    // qmlRegisterSingletonInstance into the "RingMonitor.Standalone" URI:
    // manually registering a type into a module that qt_add_qml_module already
    // owns clobbers its auto-registered C++ elements (ProcReader / NvmlReader /
    // WindowAnchor), so the QML root fails to load with "ProcReader is not a
    // type" and the binary exits 1. A context property is the right tool for
    // exposing one pre-constructed instance and leaves the module registry
    // intact. singleInstance is a stack object declared before `engine`, so it
    // outlives the engine.
    engine.rootContext()->setContextProperty("SingleInstance", &singleInstance);
    // Two physically separate roots (no `_settingsOnly` flag threaded
    // through Main.qml): recovery mode hosts only the SettingsDialog.
    const char *qmlRoot = openSettings ? "SettingsOnlyRoot" : "Main";
    engine.loadFromModule("RingMonitor.Standalone", qmlRoot);

    // Bail non-zero so a wrapper script knows QML failed to load.
    if (engine.rootObjects().isEmpty())
        return 1;

    // Per-window integration for the chosen strategy. X11Ewmh applies
    // the EWMH hints Qt can't express directly (sticky, skip-taskbar,
    // skip-pager) — PRE-MAP only, before app.exec(); see desktop_hints.h.
    // WaylandLayerShell configures + shows its layer surface from
    // Main.qml's `_anchor()` (which owns the ring-derived size and
    // margins), so there's nothing to do here for it. Floating (recovery)
    // is a normal window and needs no hints.
    if (strategy == ringmonitor::WindowStrategy::X11Ewmh) {
        if (auto *window = qobject_cast<QWindow *>(engine.rootObjects().first())) {
            ringmonitor::applyDesktopWindowHints(window);
        }
    }

    return app.exec();
}
