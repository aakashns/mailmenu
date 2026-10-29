import Foundation

/// An unread message in the inbox, with just enough detail to show in the menu.
struct UnreadMessage: Identifiable, Hashable {
    let id: String
    let threadID: String
    let senderName: String?
    let senderEmail: String
    let subject: String
    /// Set for mailing list messages that say how to unsubscribe.
    let unsubscribe: UnsubscribeMethod?

    /// Opens the conversation in Gmail on the web, in the right account even if the browser
    /// is signed into several Google accounts (or prompts to sign in if it isn't signed in).
    func gmailURL(for accountEmail: String) -> URL {
        URL(string: "https://mail.google.com/mail/?authuser=\(accountEmail.urlQueryValueEncoded)#inbox/\(threadID)")!
    }
}

/// Client for the Gmail REST API (https://developers.google.com/gmail/api/reference/rest).
struct GmailClient {
    let api: GoogleAPI

    init(accessToken: String) {
        api = GoogleAPI(accessToken: accessToken)
    }

    private static let baseURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me")!

    /// The account's inbox in Gmail on the web.
    static func inboxURL(for accountEmail: String) -> URL {
        URL(string: "https://mail.google.com/mail/?authuser=\(accountEmail.urlQueryValueEncoded)#inbox")!
    }

    func profileEmail() async throws -> String {
        let profile: Profile = try await get("profile")
        return profile.emailAddress
    }

    /// Total number of unread messages in the inbox (not limited to the ones we list).
    func inboxUnreadCount() async throws -> Int {
        let label: LabelInfo = try await get("labels/INBOX")
        return label.messagesUnread
    }

    /// The most recent unread messages in the inbox, newest first.
    func unreadInboxMessages(limit: Int) async throws -> [UnreadMessage] {
        let list: MessageList = try await get("messages", query: [
            URLQueryItem(name: "labelIds", value: "INBOX"),
            URLQueryItem(name: "labelIds", value: "UNREAD"),
            URLQueryItem(name: "maxResults", value: String(limit)),
        ])
        let ids = (list.messages ?? []).map(\.id)

        // Fetch headers for each message concurrently, then restore the list's order.
        return try await withThrowingTaskGroup(of: (Int, UnreadMessage).self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask { (index, try await message(id: id)) }
            }
            var results: [(Int, UnreadMessage)] = []
            for try await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func message(id: String) async throws -> UnreadMessage {
        let message: Message = try await get("messages/\(id)", query: [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "From"),
            URLQueryItem(name: "metadataHeaders", value: "Subject"),
            URLQueryItem(name: "metadataHeaders", value: "List-Unsubscribe"),
            URLQueryItem(name: "metadataHeaders", value: "List-Unsubscribe-Post"),
        ])
        func header(_ name: String) -> String? {
            message.payload.headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
        let sender = parseAddress(header("From") ?? "")
        return UnreadMessage(
            id: message.id,
            threadID: message.threadId,
            senderName: sender.name,
            senderEmail: sender.email,
            subject: header("Subject") ?? "",
            unsubscribe: UnsubscribeMethod(
                listUnsubscribe: header("List-Unsubscribe"),
                listUnsubscribePost: header("List-Unsubscribe-Post")
            )
        )
    }

    /// The message's body as plain text (converted from HTML if it has no plain text part), for previews.
    func bodyText(id: String) async throws -> String {
        let message: FullMessage = try await get("messages/\(id)", query: [URLQueryItem(name: "format", value: "full")])
        if let plain = message.payload.firstBody(ofType: "text/plain") {
            return plain.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let html = message.payload.firstBody(ofType: "text/html") {
            return plainText(fromHTML: html)
        }
        return ""
    }

    /// Removes the conversation from the inbox, like Gmail's Archive button.
    func archive(threadID: String) async throws {
        try await modify(threadID: threadID, add: [], remove: ["INBOX"])
    }

    /// Hides the conversation from the inbox under a "Mail Menu Snoozed" label (the Gmail API can't use
    /// Gmail's own snooze), until `unsnooze` puts it back.
    func snooze(threadID: String) async throws {
        try await modify(threadID: threadID, add: [snoozeLabelID()], remove: ["INBOX"])
    }

    /// Returns a snoozed conversation to the inbox as unread.
    func unsnooze(threadID: String) async throws {
        try await modify(threadID: threadID, add: ["INBOX", "UNREAD"], remove: [snoozeLabelID()])
    }

    private static let snoozeLabelName = "Mail Menu Snoozed"

    private func snoozeLabelID() async throws -> String {
        func find() async throws -> String? {
            let list: LabelList = try await get("labels")
            return list.labels.first { $0.name == Self.snoozeLabelName }?.id
        }
        if let id = try await find() { return id }
        try await api.post(Self.baseURL.appending(path: "labels"), body: NewLabel(name: Self.snoozeLabelName))
        guard let id = try await find() else {
            throw GoogleAPIError.requestFailed(status: 0, reason: nil, message: "Couldn't create the snooze label")
        }
        return id
    }

    /// Moves the conversation to the trash, like Gmail's Delete button.
    func trash(threadID: String) async throws {
        try await api.post(Self.baseURL.appending(path: "threads/\(threadID)/trash"), body: EmptyBody())
    }

    /// Reports the conversation as spam, and adds a filter that sends future mail from
    /// `senderEmail` straight to the trash (the Gmail API can't add to Gmail's own blocked list).
    func blockAndReportSpam(threadID: String, senderEmail: String) async throws {
        try await modify(threadID: threadID, add: ["SPAM"], remove: ["INBOX"])
        try await api.post(Self.baseURL.appending(path: "settings/filters"), body: Filter(
            criteria: .init(from: senderEmail),
            action: .init(addLabelIds: ["TRASH"], removeLabelIds: ["INBOX"])
        ))
    }

    private func modify(threadID: String, add: [String], remove: [String]) async throws {
        try await api.post(
            Self.baseURL.appending(path: "threads/\(threadID)/modify"),
            body: ModifyRequest(addLabelIds: add, removeLabelIds: remove)
        )
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await api.get(Self.baseURL.appending(path: path), query: query)
    }
}

/// Splits a From header like `"Jane Doe" <jane@example.com>` into a display name and email address.
func parseAddress(_ raw: String) -> (name: String?, email: String) {
    let raw = raw.trimmingCharacters(in: .whitespaces)
    guard let open = raw.lastIndex(of: "<"), let close = raw.lastIndex(of: ">"), open < close else {
        return (nil, raw)
    }
    let email = raw[raw.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
    let name = raw[..<open]
        .trimmingCharacters(in: .whitespaces)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    return (name.isEmpty ? nil : name, email)
}

private struct Profile: Decodable {
    let emailAddress: String
}

private struct LabelInfo: Decodable {
    let messagesUnread: Int
}

private struct LabelList: Decodable {
    struct Label: Decodable { let id: String; let name: String }
    let labels: [Label]
}

private struct NewLabel: Encodable {
    let name: String
    let labelListVisibility = "labelShow"
    let messageListVisibility = "show"
}

private struct MessageList: Decodable {
    struct Ref: Decodable { let id: String }
    let messages: [Ref]?
}

private struct Message: Decodable {
    struct Payload: Decodable { let headers: [Header] }
    struct Header: Decodable { let name: String; let value: String }
    let id: String
    let threadId: String
    let payload: Payload
}

/// A rough conversion of an HTML email to text: drops tags, styles and scripts and decodes common entities.
private func plainText(fromHTML html: String) -> String {
    var text = html
    for (pattern, replacement) in [
        ("(?is)<(style|script|head)[^>]*>.*?</\\1>", ""),
        ("(?i)<br\\s*/?>|</(p|div|tr|li|h[1-6])>", "\n"),
        ("<[^>]+>", ""),
    ] {
        text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }
    for (entity, character) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&zwnj;", "")] {
        text = text.replacingOccurrences(of: entity, with: character)
    }
    return text
        .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        .replacingOccurrences(of: "\\s*\\n\\s*", with: "\n", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private struct FullMessage: Decodable {
    struct Part: Decodable {
        struct Body: Decodable { let data: String? }
        let mimeType: String
        let body: Body?
        let parts: [Part]?

        /// The decoded text of the first part (searching nested parts too) with the given MIME type.
        func firstBody(ofType type: String) -> String? {
            if mimeType == type, let encoded = body?.data, let data = Data(base64URLEncoded: encoded) {
                return String(decoding: data, as: UTF8.self)
            }
            return parts?.lazy.compactMap { $0.firstBody(ofType: type) }.first
        }
    }
    let payload: Part
}

private extension Data {
    /// Decodes Gmail's URL-safe base64 (which may omit padding).
    init?(base64URLEncoded string: String) {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}

private struct EmptyBody: Encodable {}

private struct ModifyRequest: Encodable {
    let addLabelIds: [String]
    let removeLabelIds: [String]
}

private struct Filter: Encodable {
    struct Criteria: Encodable { let from: String }
    struct Action: Encodable { let addLabelIds: [String]; let removeLabelIds: [String] }
    let criteria: Criteria
    let action: Action
}
