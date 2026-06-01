#pragma once

// Single-instance guard + wake-up IPC for the standalone widget (issues
// #103 / #104).
//
// Problem it solves: every `ring-monitor-standalone` launch used to start
// an independent widget, so double-clicking the AppImage stacked copies on
// the wallpaper (the reporter reached four), each with a layout frozen at its
// launch time. And a config edit made from the separate `--open-settings`
// recovery process never reached the running widget (`Qt.labs.settings`
// doesn't watch the file), so settings "didn't apply" until kill+relaunch.
//
// Mechanism: the FIRST main-widget process owns a per-user QLocalServer. A
// later launch (see standalone/main.cpp) connects as a QLocalSocket client and
// writes "<intent>\n<version>". The running primary is the SOLE decider and
// replies explicitly — the newcomer never acts on a timeout (so a busy/wedged
// primary is never hijacked):
//
//   intent "open-settings" (any version) → openSettingsRequested(), reply
//       "defer": the running widget opens its IN-PROCESS SettingsDialog, whose
//       writes go through the same ConfigStore the rings read, so they apply
//       live (#104). The newcomer exits.
//   intent "show", SAME version → showRequested() (no-op: a wallpaper widget is
//       already visible), reply "defer" → the newcomer exits. No pile-up (#103).
//   intent "show", DIFFERENT version → reply "takeover", THEN supersededRequested()
//       (the widget quits) + close the server. The newcomer waits for the
//       socket to free, then becomes primary. "The AppImage you open is the one
//       that runs" — equality only, no version ordering.
//   anything else (unknown/garbled intent) → reply "defer" (never quit).
//
// Exposed to QML as a context property (`SingleInstance`) set on the engine's
// root context in main.cpp — NOT qmlRegisterSingletonInstance into the
// "RingMonitor.Standalone" URI, which would clobber the C++ elements
// qt_add_qml_module auto-registers there (ProcReader / NvmlReader / WindowAnchor)
// and make the QML root fail to load. It is also NOT QML_ELEMENT/QML_SINGLETON
// because the engine would lazily construct its own instance, whereas QML must
// connect to the very object main.cpp called listen() on.

#include <QObject>
#include <QString>

class QLocalServer;

// Wire protocol shared by both ends (main.cpp client, single_instance.cpp
// server) so the tokens are defined once — a bare-literal typo on one side
// would silently break the handshake (e.g. an unrecognised reply → the
// newcomer never takes over). One message per connection, framed as a single
// newline-terminated line: "<intent> <version>\n". The terminating '\n' is the
// frame delimiter, so reading up to the first '\n' guarantees the WHOLE message
// (intent AND version) arrived — a split delivery can't truncate the version.
namespace SingleInstanceProtocol {
inline constexpr char kIntentOpenSettings[] = "open-settings";
inline constexpr char kIntentShow[] = "show";
inline constexpr char kReplyDefer[] = "defer";       // newcomer exits
inline constexpr char kReplyTakeover[] = "takeover";  // newcomer claims the socket
}

class SingleInstance : public QObject
{
    Q_OBJECT

public:
    // localVersion is this build's KPlugin.Version (RING_MONITOR_VERSION),
    // compared against the version a later launch announces.
    explicit SingleInstance(QString localVersion, QObject *parent = nullptr);

    enum class Claim {
        Acquired,  // we now own the socket and are the primary
        Busy,      // a live primary won the race — caller should re-probe and defer
        Failed,    // listen() failed for a non-recoverable reason
    };

    // Try to become the primary by listening on `name`. Race-safe: tries
    // listen() FIRST and, only if that fails, RE-PROBES the socket — a live
    // owner means Busy (we must NOT remove its socket); a dead socket file
    // (crashed primary) is cleared with removeServer() and listen() retried.
    // This never blindly unlinks a live primary's socket (review finding #1).
    Claim tryListen(const QString &name);

Q_SIGNALS:
    void openSettingsRequested();
    void showRequested();
    void supersededRequested();

private Q_SLOTS:
    void onNewConnection();

private:
    QString m_localVersion;
    QLocalServer *m_server = nullptr;
};
