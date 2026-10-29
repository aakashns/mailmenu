import Foundation

/// How to unsubscribe from a mailing list, from a message's `List-Unsubscribe` headers.
enum UnsubscribeMethod: Hashable {
    /// RFC 8058 one-click unsubscribe: a POST to this URL unsubscribes without any further steps.
    case oneClick(URL)
    /// A web page where the user confirms unsubscribing.
    case website(URL)
    /// A `mailto:` link; sending the email unsubscribes.
    case email(URL)

    /// Parses headers like `List-Unsubscribe: <mailto:unsub@example.com>, <https://example.com/u/123>`
    /// and `List-Unsubscribe-Post: List-Unsubscribe=One-Click`, preferring one-click, then a web page, then email.
    init?(listUnsubscribe: String?, listUnsubscribePost: String?) {
        guard let listUnsubscribe else { return nil }
        let urls = listUnsubscribe
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "<>")) }
            .compactMap { URL(string: $0) }
        let webURL = urls.first { $0.scheme?.lowercased() == "https" }
            ?? urls.first { $0.scheme?.lowercased() == "http" }
        let supportsOneClick = listUnsubscribePost?.contains("List-Unsubscribe=One-Click") == true

        if let webURL, supportsOneClick, webURL.scheme?.lowercased() == "https" {
            self = .oneClick(webURL)
        } else if let webURL {
            self = .website(webURL)
        } else if let mailto = urls.first(where: { $0.scheme?.lowercased() == "mailto" }) {
            self = .email(mailto)
        } else {
            return nil
        }
    }
}

enum UnsubscribeError: LocalizedError {
    case failed(status: Int)

    var errorDescription: String? {
        switch self {
        case .failed(let status): "Unsubscribe failed (HTTP \(status))"
        }
    }
}

/// Sends an RFC 8058 one-click unsubscribe request.
func unsubscribeWithOneClick(_ url: URL) async throws {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data("List-Unsubscribe=One-Click".utf8)

    let (_, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else { throw UnsubscribeError.failed(status: status) }
}

/// Gmail on the web's compose window, filled in from a `mailto:` link and sent from the given account.
func gmailComposeURL(for mailto: URL, accountEmail: String) -> URL {
    let mailtoComponents = URLComponents(url: mailto, resolvingAgainstBaseURL: false)
    func field(_ name: String) -> String? {
        mailtoComponents?.queryItems?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    var components = URLComponents(string: "https://mail.google.com/mail/")!
    components.queryItems = [
        URLQueryItem(name: "authuser", value: accountEmail),
        URLQueryItem(name: "view", value: "cm"),
        URLQueryItem(name: "fs", value: "1"),
        URLQueryItem(name: "to", value: mailtoComponents?.path ?? ""),
        URLQueryItem(name: "su", value: field("subject") ?? "Unsubscribe"),
        URLQueryItem(name: "body", value: field("body") ?? ""),
    ]
    return components.url!
}
