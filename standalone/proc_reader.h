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
    // I/O error). Callers (typically a `Timer.onTriggered` in QML)
    // are expected to tolerate empty / partial input — the
    // `ProcStatParser` helpers in `core/` do.
    Q_INVOKABLE QString read(const QString &path) const;
};
