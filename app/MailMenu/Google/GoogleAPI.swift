import Foundation

enum GoogleAPIError: LocalizedError {
    case requestFailed(status: Int, reason: String?, message: String?)

    /// Machine-readable reason from Google's error response, e.g. "insufficientPermissions".
    var reason: String? {
        switch self {
        case .requestFailed(_, let reason, _): reason
        }
    }

    var errorDescription: String? {
        switch self {
        case .requestFailed(let status, _, let message):
            "Google request failed (HTTP \(status))" + (message.map { ": \($0)" } ?? "")
        }
    }
}

/// Sends authorized GET requests to Google's REST APIs and decodes the JSON responses.
struct GoogleAPI {
    let accessToken: String

    func get<T: Decodable>(_ url: URL, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let error = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error
            throw GoogleAPIError.requestFailed(status: status, reason: error?.errors?.first?.reason, message: error?.message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

extension String {
    /// Percent-encodes the string for use as a URL query value (e.g. an email address in `authuser=`).
    var urlQueryValueEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? self
    }
}

private struct APIErrorResponse: Decodable {
    struct Body: Decodable {
        struct Detail: Decodable { let reason: String? }
        let message: String
        let errors: [Detail]?
    }
    let error: Body
}
