import AppKit
import Observation

/// App-wide state: the signed-in Google account and its unread inbox messages.
@Observable
final class AppModel {
    private(set) var account: GoogleAccount?
    private(set) var messages: [UnreadMessage] = []
    private(set) var isSigningIn = false
    private(set) var isRefreshing = false
    private(set) var lastRefreshed: Date?
    var errorMessage: String?

    let oauthConfig = GoogleOAuthConfig.fromBundle()

    private let auth = GoogleAuth()
    private var accessToken: AccessToken?

    private static let keychainAccount = "google"
    private static let gmailScopes = ["https://www.googleapis.com/auth/gmail.readonly"]

    init() {
        if let data = Keychain.load(account: Self.keychainAccount) {
            account = try? JSONDecoder().decode(GoogleAccount.self, from: data)
        }
    }

    func signIn() async {
        guard let oauthConfig, !isSigningIn else { return }
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            let tokens = try await auth.signIn(config: oauthConfig, scopes: Self.gmailScopes)
            guard let refreshToken = tokens.refreshToken else { throw GoogleAuthError.missingRefreshToken }
            let token = tokens.accessToken
            let email = try await GmailClient(accessToken: token.value).profileEmail()
            let account = GoogleAccount(email: email, refreshToken: refreshToken)
            try Keychain.save(JSONEncoder().encode(account), account: Self.keychainAccount)
            self.account = account
            self.accessToken = token
            await refresh()
        } catch GoogleAuthError.cancelled {
            // User closed the sign-in window; nothing to report.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        Keychain.delete(account: Self.keychainAccount)
        account = nil
        accessToken = nil
        messages = []
        lastRefreshed = nil
        errorMessage = nil
    }

    func refresh() async {
        guard let account, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let token = try await validAccessToken(for: account)
            messages = try await GmailClient(accessToken: token).unreadInboxMessages(limit: 25)
            lastRefreshed = .now
            errorMessage = nil
        } catch GoogleAuthError.invalidGrant {
            // Refresh token was revoked or expired (tokens expire after 7 days while the
            // Google Cloud app is in "Testing" mode), so the user has to sign in again.
            signOut()
            errorMessage = "Your Google session expired. Please sign in again."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func open(_ message: UnreadMessage) {
        guard let account else { return }
        NSWorkspace.shared.open(message.gmailURL(for: account.email))
    }

    private func validAccessToken(for account: GoogleAccount) async throws -> String {
        if let accessToken, accessToken.isValid {
            return accessToken.value
        }
        guard let oauthConfig else { throw GoogleAuthError.notConfigured }
        let token = try await auth.refresh(config: oauthConfig, refreshToken: account.refreshToken)
        accessToken = token
        return token.value
    }
}

/// A signed-in Google account, persisted in the Keychain.
struct GoogleAccount: Codable {
    var email: String
    var refreshToken: String
}
