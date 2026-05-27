#pragma once

// Tiny QML-callable helper for reading text files from the standalone
// build (currently used to pull `/proc/stat`, `/proc/meminfo`, etc.).
//
// Why a C++ helper instead of QML's XMLHttpRequest with `file://`:
// since Qt 6.5 only the file scheme is exposed and the QML loading
// context has to itself live under file:// for the read to be
// allowed. Our QML is loaded from the compiled qrc:// resource (via
// `qt_add_qml_module` + `loadFromModule`), so file:// XHR is
// blocked. A dedicated `Q_INVOKABLE` doesn't carry that restriction.
//
// Registered to QML via the `QML_ELEMENT` macro picked up by
// `qt_add_qml_module(... SOURCES proc_reader.cpp …)`. Available in
// QML as `import RingMonitor.Standalone; ProcReader { id: reader }`.

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QtQmlIntegration/QtQmlIntegration>

// Lives at global scope rather than in `ringmonitor::` because
// Qt 6's `QML_ELEMENT` auto-registration generates code calling
// `qmlRegisterTypesAndRevisions<ProcReader>(…)` without
// namespace-qualifying the type — a namespaced class needs
// `QML_FOREIGN_NAMESPACE` boilerplate to register cleanly. The
// helper is a thin one-method utility, so the lower-friction
// global-scope path is the right trade-off.

class ProcReader : public QObject
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit ProcReader(QObject *parent = nullptr) : QObject(parent) {}

    // Synchronous read. Returns the file contents on success, an
    // empty string on any failure (missing file, no read permission,
    // I/O error, **or path outside the `/proc/` / `/sys/` allowlist**).
    // Callers (typically a `Timer.onTriggered` in QML) are expected to
    // tolerate empty / partial input — the `ProcStatParser` helpers in
    // `core/` do. The allowlist exists because `Q_INVOKABLE` exposes
    // this to every QML context and a leaf calling `read("/etc/...")`
    // would otherwise turn the helper into an arbitrary file-read
    // primitive.
    Q_INVOKABLE QString read(const QString &path) const;

    // statvfs(3) wrapper. Returns { "total": <bytes>, "free":
    // <bytes>, "available": <bytes> } on success; empty map on any
    // failure (path missing, not mounted, EACCES). All three fields
    // are in bytes (`f_X * f_frsize`):
    //   - `total`     = f_blocks (filesystem-wide size, includes
    //                   root reservation)
    //   - `free`      = f_bfree  (all unused blocks, including the
    //                   root reservation)
    //   - `available` = f_bavail (unused blocks reachable by an
    //                   unprivileged user; matches `df`'s "Avail")
    //
    // Both `free` and `available` are exposed so QML can compute
    // df(1)'s "Use%" formula `(total - free) / (total - free +
    // available)` via `MemInfoParser.diskUsagePercent`. The naive
    // `(total - available) / total` would count the ~5% ext4 root
    // reservation as "used" and report a non-zero usage on a
    // freshly-formatted empty filesystem.
    Q_INVOKABLE QVariantMap statvfs(const QString &path) const;
};
