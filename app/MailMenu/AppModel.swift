import AppKit
import Observation

/// App-wide state: the signed-in Google accounts, their unread mail and upcoming events.
@Observable
final class AppModel {
    private(set) var accounts: [GoogleAccount] = []
    private(set) var isSigningIn = false
    var errorMessage: String?

    let oauthConfig = GoogleOAuthConfig.fromBundle()

    private let auth = GoogleAuth()

    private static let keychainAccount = "google"
    private static let scopes = [
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/calendar.events.readonly",
    ]
    private static let refreshInterval: Duration = .seconds(120)
    private static let upcomingWindow: TimeInterval = 24 * 60 * 60

    /// Unread inbox messages across all accounts, shown next to the menu bar icon.
    var totalUnreadCount: Int {
        accounts.compactMap(\.unreadCount).reduce(0, +)
    }

    init() {
        accounts = Self.loadSavedAccounts().map { GoogleAccount(email: $0.email, refreshToken: $0.refreshToken) }
        Task { await refreshPeriodically() }
    }

    private func refreshPeriodically() async {
        while true {
            await refreshAll()
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }

    /// Signs in with Google and adds the account, or updates its credentials if it was already added.
    func addAccount() async {
        guard let oauthConfig, !isSigningIn else { return }
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            let tokens = try await auth.signIn(config: oauthConfig, scopes: Self.scopes)
            guard let refreshToken = tokens.refreshToken else { throw GoogleAuthError.missingRefreshToken }
            let email = try await GmailClient(accessToken: tokens.accessToken.value).profileEmail()

            let account: GoogleAccount
            if let existing = accounts.first(where: { $0.email == email }) {
                account = existing
                account.refreshToken = refreshToken
            } else {
                account = GoogleAccount(email: email, refreshToken: refreshToken)
                accounts.append(account)
            }
            account.accessToken = tokens.accessToken
            try saveAccounts()
            await refresh(account)
        } catch GoogleAuthError.cancelled {
            // User closed the sign-in window; nothing to report.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut(_ account: GoogleAccount) {
        accounts.removeAll { $0 === account }
        do {
            try saveAccounts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshAll() async {
        await withDiscardingTaskGroup { group in
            for account in accounts {
                group.addTask { await self.refresh(account) }
            }
        }
    }

    func refresh(_ account: GoogleAccount) async {
        guard !account.isRefreshing else { return }
        account.isRefreshing = true
        defer { account.isRefreshing = false }

        let token: String
        do {
            token = try await validAccessToken(for: account)
        } catch GoogleAuthError.invalidGrant {
            // Refresh token was revoked or expired (tokens expire after 7 days while the
            // Google Cloud app is in "Testing" mode), so the user has to sign in again.
            signOut(account)
            errorMessage = "Your Google session for \(account.email) expired. Please add the account again."
            return
        } catch {
            account.errorMessage = error.localizedDescription
            return
        }

        async let mail: Void = refreshMail(account, token: token)
        async let calendar: Void = refreshCalendar(account, token: token)
        _ = await (mail, calendar)
    }

    private func refreshMail(_ account: GoogleAccount, token: String) async {
        do {
            let client = GmailClient(accessToken: token)
            async let messages = client.unreadInboxMessages(limit: 25)
            async let unreadCount = client.inboxUnreadCount()
            (account.messages, account.unreadCount) = try await (messages, unreadCount)
            account.lastRefreshed = .now
            account.errorMessage = nil
        } catch {
            account.errorMessage = error.localizedDescription
        }
    }

    private func refreshCalendar(_ account: GoogleAccount, token: String) async {
        do {
            let now = Date.now
            account.events = try await CalendarClient(accessToken: token)
                .events(from: now, to: now.addingTimeInterval(Self.upcomingWindow), accountEmail: account.email)
            account.calendarErrorMessage = nil
        } catch let error as GoogleAPIError where error.reason == "insufficientPermissions" {
            // Accounts added before calendar support (or where the user unticked calendar
            // access on Google's consent screen) need to sign in again to grant it.
            account.calendarErrorMessage = "No calendar access. Click Add Account and choose this account again to allow it."
        } catch {
            account.calendarErrorMessage = error.localizedDescription
        }
    }

    func open(_ message: UnreadMessage, in account: GoogleAccount) {
        NSWorkspace.shared.open(message.gmailURL(for: account.email))
    }

    func open(_ event: CalendarEvent) {
        if let url = event.url {
            NSWorkspace.shared.open(url)
        }
    }

    private func validAccessToken(for account: GoogleAccount) async throws -> String {
        if let accessToken = account.accessToken, accessToken.isValid {
            return accessToken.value
        }
        guard let oauthConfig else { throw GoogleAuthError.notConfigured }
        let token = try await auth.refresh(config: oauthConfig, refreshToken: account.refreshToken)
        account.accessToken = token
        return token.value
    }

    // MARK: Persistence

    private func saveAccounts() throws {
        let saved = accounts.map { SavedAccount(email: $0.email, refreshToken: $0.refreshToken) }
        try Keychain.save(JSONEncoder().encode(saved), account: Self.keychainAccount)
    }

    private static func loadSavedAccounts() -> [SavedAccount] {
        guard let data = Keychain.load(account: keychainAccount) else { return [] }
        if let accounts = try? JSONDecoder().decode([SavedAccount].self, from: data) {
            return accounts
        }
        // Versions before multi-account support saved a single account.
        if let account = try? JSONDecoder().decode(SavedAccount.self, from: data) {
            return [account]
        }
        return []
    }
}

/// A signed-in Google account with its unread inbox messages and upcoming events.
@Observable
final class GoogleAccount: Identifiable {
    let email: String
    fileprivate(set) var refreshToken: String
    fileprivate(set) var messages: [UnreadMessage] = []
    fileprivate(set) var unreadCount: Int?
    fileprivate(set) var isRefreshing = false
    fileprivate(set) var lastRefreshed: Date?
    fileprivate(set) var errorMessage: String?
    /// Nil until the calendar has been loaded.
    fileprivate(set) var events: [CalendarEvent]?
    fileprivate(set) var calendarErrorMessage: String?
    fileprivate var accessToken: AccessToken?

    var id: String { email }

    /// Events that haven't ended yet, soonest first.
    var upcomingEvents: [CalendarEvent] {
        let now = Date.now
        return (events ?? []).filter { $0.end > now }
    }

    init(email: String, refreshToken: String) {
        self.email = email
        self.refreshToken = refreshToken
    }
}

/// The part of an account persisted in the Keychain.
private struct SavedAccount: Codable {
    var email: String
    var refreshToken: String
}
