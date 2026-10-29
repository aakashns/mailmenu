import Foundation

/// Answers the app's requests to Google (and anywhere else) in demo mode, from an in-memory copy of the fake
/// mailboxes and calendars in `DemoData`. Archiving, deleting, snoozing etc. change that state like Gmail would,
/// so the lists and counts update as expected. Every response is a little delayed, like a real server.
///
/// Mail from `DemoData.failingSender` can't be changed: actions on it fail, to test how errors look.
nonisolated final class FakeGoogleServer: URLProtocol {
    /// All demo accounts, in the order "Continue with Google" adds them.
    static var accountEmails: [String] { DemoData.mailboxes.map(\.email) }

    private static let state = State()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = request
        let body = request.httpBody ?? request.httpBodyStream.map(Self.readAll) ?? Data()
        let delay = Double.random(in: 0.2...0.6)
        let connection = Connection(urlProtocol: self)
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            let server = connection.urlProtocol
            let (status, json) = Self.state.respond(to: request, body: body)
            let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            server.client?.urlProtocol(server, didReceive: response, cacheStoragePolicy: .notAllowed)
            server.client?.urlProtocol(server, didLoad: data)
            server.client?.urlProtocolDidFinishLoading(server)
        }
    }

    override func stopLoading() {}

    /// Lets the delayed response reach the URL loading system, which keeps the protocol alive until it finishes.
    private struct Connection: @unchecked Sendable {
        let urlProtocol: FakeGoogleServer
    }

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    /// The mutable mailboxes, shared by requests running on different threads.
    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var mailboxes = DemoData.mailboxes
        private var snoozeLabelCreated = false

        private static let snoozeLabelID = "Label_snoozed"

        func respond(to request: URLRequest, body: Data) -> (Int, Any) {
            lock.lock()
            defer { lock.unlock() }
            guard let url = request.url else { return notFound() }
            let path = url.path()
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let input = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]

            switch (url.host() ?? "", request.httpMethod ?? "GET") {
            case ("oauth2.googleapis.com", _):
                // Token refresh: the access token names the account, like the refresh token.
                let form = URLComponents(string: "?" + String(decoding: body, as: UTF8.self))?.queryItems ?? []
                let refreshToken = form.first { $0.name == "refresh_token" }?.value ?? ""
                return (200, ["access_token": refreshToken, "expires_in": 3600])
            case ("gmail.googleapis.com", let method):
                guard let index = mailboxIndex(for: request) else { return unauthorized() }
                return gmail(method, path: path.replacing("/gmail/v1/users/me/", with: ""), query: query,
                             input: input, mailbox: &mailboxes[index])
            case ("www.googleapis.com", _) where path.hasPrefix("/calendar/v3/"):
                guard let index = mailboxIndex(for: request) else { return unauthorized() }
                return (200, ["items": mailboxes[index].events.map { $0.json() }])
            default:
                // Anything else (like a one-click unsubscribe link) just succeeds, without leaving the Mac.
                return (200, [String: Any]())
            }
        }

        private func gmail(_ method: String, path: String, query: [URLQueryItem], input: [String: Any],
                           mailbox: inout DemoData.Mailbox) -> (Int, Any) {
            let parts = path.split(separator: "/").map(String.init)
            switch (method, parts.first ?? "", parts.count) {
            case ("GET", "profile", 1):
                return (200, ["emailAddress": mailbox.email])
            case ("GET", "labels", 2) where parts[1] == "INBOX":
                let inbox = mailbox.messages.filter { $0.labels.contains("INBOX") }
                return (200, ["messagesTotal": inbox.count, "messagesUnread": inbox.filter { $0.labels.contains("UNREAD") }.count])
            case ("GET", "labels", 1):
                let labels = snoozeLabelCreated ? [["id": Self.snoozeLabelID, "name": "Mail Menu Snoozed"]] : []
                return (200, ["labels": labels])
            case ("POST", "labels", 1):
                snoozeLabelCreated = true
                return (200, ["id": Self.snoozeLabelID])
            case ("GET", "messages", 1):
                let labelIDs = query.filter { $0.name == "labelIds" }.compactMap(\.value)
                let limit = query.first { $0.name == "maxResults" }?.value.flatMap(Int.init) ?? 100
                let matches = mailbox.messages.filter { message in labelIDs.allSatisfy(message.labels.contains) }
                return (200, ["messages": matches.prefix(limit).map { ["id": $0.id, "threadId": $0.threadID] }])
            case ("GET", "messages", 2):
                guard let message = mailbox.messages.first(where: { $0.id == parts[1] }) else { return notFound() }
                let full = query.contains { $0.name == "format" && $0.value == "full" }
                return (200, full ? message.fullJSON() : message.metadataJSON())
            case ("POST", "threads", 3):
                let threadID = parts[1]
                guard mailbox.messages.contains(where: { $0.threadID == threadID }) else { return notFound() }
                if mailbox.messages.contains(where: { $0.threadID == threadID && $0.sender.contains(DemoData.failingSender) }) {
                    return (500, ["error": ["message": "Simulated failure in demo mode", "errors": [["reason": "backendError"]]]])
                }
                let add = parts[2] == "trash" ? ["TRASH"] : input["addLabelIds"] as? [String] ?? []
                let remove = parts[2] == "trash" ? ["INBOX"] : input["removeLabelIds"] as? [String] ?? []
                for index in mailbox.messages.indices where mailbox.messages[index].threadID == threadID {
                    mailbox.messages[index].labels.subtract(remove)
                    mailbox.messages[index].labels.formUnion(add)
                }
                return (200, [String: Any]())
            case ("POST", "settings", 2) where parts[1] == "filters":
                return (200, ["id": UUID().uuidString])
            default:
                return notFound()
            }
        }

        private func mailboxIndex(for request: URLRequest) -> Array<DemoData.Mailbox>.Index? {
            let token = request.value(forHTTPHeaderField: "Authorization")?.replacing("Bearer ", with: "")
            return mailboxes.firstIndex { DemoMode.refreshToken(for: $0.email) == token }
        }

        private func notFound() -> (Int, Any) {
            (404, ["error": ["message": "Not found", "errors": [["reason": "notFound"]]]])
        }

        private func unauthorized() -> (Int, Any) {
            (401, ["error": ["message": "Invalid credentials", "errors": [["reason": "authError"]]]])
        }
    }
}
