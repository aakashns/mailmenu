import Foundation

/// Runs the app against a fake Google server with made-up accounts, mail and events, for development,
/// screenshots and testing. Turn it on by launching with `--demo` (see `scripts/demo.sh`).
///
/// The real Gmail and Calendar clients run as usual: every request they make is answered in memory by
/// `FakeGoogleServer`, and nothing is sent over the network. Accounts aren't read from or saved to the
/// Keychain, and all data resets when the app quits.
enum DemoMode {
    nonisolated static let isEnabled = ProcessInfo.processInfo.arguments.contains("--demo")
        || ProcessInfo.processInfo.environment["MAILMENU_DEMO"] == "1"

    /// Accounts signed in at launch.
    static let initialAccounts = ["alex@example.com", "alex.personal@example.com"]

    static let oauthConfig = GoogleOAuthConfig(clientID: "demo.apps.googleusercontent.com")

    /// Snooze times etc., kept apart from the real app's settings and cleared on every launch.
    static let defaults: UserDefaults = {
        let name = "app.mailmenu.MailMenu.demo"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }()

    static func start() {
        URLProtocol.registerClass(FakeGoogleServer.self)
    }

    /// The refresh token for a demo account. The fake server hands out access tokens that name the account.
    nonisolated static func refreshToken(for email: String) -> String { "demo:\(email)" }

    /// What "Continue with Google" signs into: the next demo account that isn't signed in yet.
    static func signIn(excluding signedIn: [String]) async throws -> GoogleTokens {
        try await Task.sleep(for: .milliseconds(600))
        guard let email = FakeGoogleServer.accountEmails.first(where: { !signedIn.contains($0) }) else {
            throw GoogleAuthError.tokenRequestFailed("All demo accounts are already added.")
        }
        return GoogleTokens(accessToken: AccessToken(value: refreshToken(for: email), expiresAt: .now.addingTimeInterval(3600)),
                            refreshToken: refreshToken(for: email))
    }
}
