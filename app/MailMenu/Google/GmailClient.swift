import Foundation

/// An unread message in the inbox, with just enough detail to show in the menu.
struct UnreadMessage: Identifiable, Hashable {
    let id: String
    let threadID: String
    let senderName: String?
    let senderEmail: String
    let subject: String

    /// Opens the conversation in Gmail on the web, in the right account even if the browser
    /// is signed into several Google accounts (or prompts to sign in if it isn't signed in).
    func gmailURL(for accountEmail: String) -> URL {
        let email = accountEmail.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? accountEmail
        return URL(string: "https://mail.google.com/mail/?authuser=\(email)#inbox/\(threadID)")!
    }
}

enum GmailError: LocalizedError {
    case requestFailed(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let status, let message):
            "Gmail request failed (HTTP \(status))" + (message.map { ": \($0)" } ?? "")
        }
    }
}

/// Read-only client for the Gmail REST API (https://developers.google.com/gmail/api/reference/rest).
struct GmailClient {
    let accessToken: String

    private static let baseURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me")!

    func profileEmail() async throws -> String {
        let profile: Profile = try await get("profile")
        return profile.emailAddress
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
            subject: header("Subject") ?? ""
        )
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: Self.baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error.message
            throw GmailError.requestFailed(status: status, message: message)
        }
        return try JSONDecoder().decode(T.self, from: data)
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

private struct APIErrorResponse: Decodable {
    struct Body: Decodable { let message: String }
    let error: Body
}
