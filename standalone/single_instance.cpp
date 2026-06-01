#include "single_instance.h"

#include <QAbstractSocket>
#include <QLocalServer>
#include <QLocalSocket>

#include <utility>

SingleInstance::SingleInstance(QString localVersion, QObject *parent)
    : QObject(parent)
    , m_localVersion(std::move(localVersion))
{
}

SingleInstance::Claim SingleInstance::tryListen(const QString &name)
{
    m_server = new QLocalServer(this);
    // Try to listen WITHOUT removing the socket first — so a live primary's
    // socket is never blindly unlinked (review finding #1). On Unix a leftover
    // socket file from a crashed primary makes listen() fail with
    // AddressInUseError; only then do we distinguish "stale file" from "live
    // owner" by probing.
    if (m_server->listen(name)) {
        connect(m_server, &QLocalServer::newConnection, this, &SingleInstance::onNewConnection);
        return Claim::Acquired;
    }
    if (m_server->serverError() == QAbstractSocket::AddressInUseError) {
        // Is someone actually listening, or is this a stale socket file?
        QLocalSocket probe;
        probe.connectToServer(name);
        const bool liveOwner = probe.waitForConnected(100);
        probe.abort();
        if (liveOwner) {
            delete m_server;
            m_server = nullptr;
            return Claim::Busy;  // a primary won the race — caller re-probes + defers
        }
        // Stale socket file: safe to clear (no live owner answered) and retry.
        QLocalServer::removeServer(name);
        if (m_server->listen(name)) {
            connect(m_server, &QLocalServer::newConnection, this, &SingleInstance::onNewConnection);
            return Claim::Acquired;
        }
    }
    delete m_server;
    m_server = nullptr;
    return Claim::Failed;
}

void SingleInstance::onNewConnection()
{
    using namespace SingleInstanceProtocol;
    QLocalSocket *client = m_server->nextPendingConnection();
    if (!client)
        return;
    // One message per connection, framed as a single newline-terminated line
    // "<intent> <version>\n". Read until that terminating '\n' arrives — its
    // presence proves the WHOLE line (intent AND version) is here, so a split
    // delivery can't truncate the version (review finding F1). The space split
    // means the version field is everything after the first space, before '\n'.
    QByteArray payload = client->readAll();
    while (!payload.contains('\n') && client->waitForReadyRead(200))
        payload += client->readAll();
    const QByteArray line = payload.left(payload.indexOf('\n')).trimmed();
    const int sp = line.indexOf(' ');
    const QByteArray intent = (sp >= 0 ? line.left(sp) : line);
    const QString version = (sp >= 0 ? QString::fromUtf8(line.mid(sp + 1)) : QString()).trimmed();

    const auto reply = [client](const char *token) {
        client->write(token);
        client->write("\n");
        client->flush();
        client->waitForBytesWritten(100);
    };

    if (intent == kIntentShow && !version.isEmpty() && version != m_localVersion) {
        // Different build launched: hand over. Reply "takeover" BEFORE quitting
        // so the newcomer reliably reads it (it only takes over on this explicit
        // reply, never on a timeout — review findings #1/#2). Then quit and close
        // the server synchronously so the socket is freed deterministically
        // before the newcomer's tryListen() (no late-dtor unlink race).
        reply(kReplyTakeover);
        Q_EMIT supersededRequested();
        if (m_server)
            m_server->close();
    } else {
        // open-settings (any version), same-version show, or any unknown/garbled
        // intent → the running widget stays; the newcomer exits. An unrecognised
        // intent must NEVER quit the widget (review finding #3).
        if (intent == kIntentOpenSettings)
            Q_EMIT openSettingsRequested();
        else if (intent == kIntentShow)
            Q_EMIT showRequested();
        reply(kReplyDefer);
    }
    client->disconnectFromServer();
    client->deleteLater();
}
