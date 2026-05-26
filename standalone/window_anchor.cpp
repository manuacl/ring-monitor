#include "window_anchor.h"

#include <QRect>
#include <QWindow>

WindowAnchor::WindowAnchor(QObject *parent)
    : QObject(parent)
{
}

void WindowAnchor::setGeometry(QObject *window, int x, int y, int width, int height)
{
    // QML passes the `Window { id: root }` as a QObject*; it's a
    // QQuickWindow at runtime, which inherits QWindow. qobject_cast
    // is the safe downcast — returns nullptr if the caller passed
    // something else (e.g. an Item by mistake).
    if (auto *w = qobject_cast<QWindow *>(window)) {
        w->setGeometry(QRect(x, y, width, height));
    }
}
