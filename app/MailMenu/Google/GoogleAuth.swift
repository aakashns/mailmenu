import AppKit
import AuthenticationServices
import CryptoKit
import Foundation

/// OAuth client settings, read from the app's Info.plist (set via GOOGLE_CLIENT_ID in Local.xcconfig).
struct GoogleOAuthConfig {
    /// Client ID of an "iOS" type OAuth client, which doesn't need a client secret.
    let clientID: String

    /// Google's iOS clients accept the reversed client ID as a custom URL scheme for redirects.
    var redirectScheme: String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    var redirectURI: String { "\(redirectScheme):/oauth2redirect" }

    static func fromBundle() -> GoogleOAuthConfig? {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String,
              clientID.hasSuffix(".apps.googleusercontent.com"),
              !clientID.contains(where: { $0.isWhitespace || $0 == "=" })
        else { return nil }
        return GoogleOAuthConfig(clientID: clientID)
    }
}

struct AccessToken {
    let value: String
    let expiresAt: Date

    /// Treat tokens as expired a minute early to avoid racing the expiry.
    var isValid: Bool { expiresAt.timeIntervalSinceNow > 60 }
}

struct GoogleTokens {
    let accessToken: AccessToken
    let refreshToken: String?
}

enum GoogleAuthError: LocalizedError {
    case notConfigured
    case cancelled
    case invalidCallback
    case missingRefreshToken
    case invalidGrant
    case tokenRequestFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Google client ID is not configured."
        case .cancelled: "Sign-in was cancelled."
        case .invalidCallback: "Google returned an unexpected sign-in response."
        case .missingRefreshToken: "Google didn't return a refresh token. Please try signing in again."
        case .invalidGrant: "Your Google session has expired."
        case .tokenRequestFailed(let message): "Google sign-in failed: \(message)"
        }
    }
}

/// Signs in with Google using OAuth 2.0 for native apps (authorization code flow with PKCE),
/// via the system's web authentication session, and refreshes access tokens.
final class GoogleAuth: NSObject {
    private static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    /// Retained while the sign-in window is open.
    private var session: ASWebAuthenticationSession?

    func signIn(config: GoogleOAuthConfig, scopes: [String]) async throws -> GoogleTokens {
        let verifier = Self.randomURLSafeString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        let state = Self.randomURLSafeString()

        var components = URLComponents(url: Self.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]

        let callbackURL = try await authenticate(url: components.url!, callbackScheme: config.redirectScheme)

        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let error = value("error") {
            throw error == "access_denied" ? GoogleAuthError.cancelled : GoogleAuthError.tokenRequestFailed(error)
        }
        guard value("state") == state, let code = value("code") else {
            throw GoogleAuthError.invalidCallback
        }

        return try await requestTokens([
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
            "client_id": config.clientID,
            "redirect_uri": config.redirectURI,
        ])
    }

    func refresh(config: GoogleOAuthConfig, refreshToken: String) async throws -> AccessToken {
        try await requestTokens([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientID,
        ]).accessToken
    }

    private func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        defer { session = nil }
        return try await withCheckedThrowingContinuation { continuation in
            // @Sendable keeps this handler off the main actor: the system may call it on a
            // background queue, which would otherwise trip Swift's main-actor isolation check.
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { @Sendable url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: GoogleAuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? GoogleAuthError.invalidCallback)
                }
            }
            session.presentationContextProvider = self
            self.session = session
            NSApp.activate()
            session.start()
        }
    }

    private func requestTokens(_ parameters: [String: String]) async throws -> GoogleTokens {
        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((body.percentEncodedQuery ?? "").utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard status == 200 else {
            let error = try? JSONDecoder().decode(TokenErrorResponse.self, from: data)
            if error?.error == "invalid_grant" { throw GoogleAuthError.invalidGrant }
            throw GoogleAuthError.tokenRequestFailed(error?.errorDescription ?? error?.error ?? "HTTP \(status)")
        }

        let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)
        return GoogleTokens(
            accessToken: AccessToken(value: tokens.accessToken, expiresAt: .now.addingTimeInterval(tokens.expiresIn)),
            refreshToken: tokens.refreshToken
        )
    }

    private static func randomURLSafeString() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
}

extension GoogleAuth: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? ASPresentationAnchor()
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let expiresIn: TimeInterval
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

private struct TokenErrorResponse: Decodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
