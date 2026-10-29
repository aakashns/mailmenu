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
    @ObservationIgnored private var previews: [String: String] = [:]

    private static let keychainAccount = "google"
    private static let scopes = [
        "https://www.googleapis.com/auth/gmail.modify",
        "https://www.googleapis.com/auth/gmail.settings.basic",
        "https://www.googleapis.com/auth/calendar.events.readonly",
    ]
    private static let refreshInterval: Duration = .seconds(120)
    private static let upcomingWindow: TimeInterval = 24 * 60 * 60
    private static let previewLength = 1500
    private static let acknowledgementDuration: Duration = .seconds(3)

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
        account.hasLoaded = true
    }

    private func refreshMail(_ account: GoogleAccount, token: String) async {
        do {
            let client = GmailClient(accessToken: token)
            async let messages = client.unreadInboxMessages(limit: 25)
            async let unreadCount = client.inboxUnreadCount()
            var fetched = try await messages
            // Rows showing an acknowledgement stay put until it ends, even though they're no longer unread in the inbox.
            for (index, message) in account.messages.enumerated()
            where account.acknowledgements[message.threadID] != nil
                && !fetched.contains(where: { $0.threadID == message.threadID }) {
                fetched.insert(message, at: min(index, fetched.count))
            }
            (account.messages, account.unreadCount) = (fetched, try await unreadCount)
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

    func archive(_ message: UnreadMessage, in account: GoogleAccount) async {
        await performMailAction(on: message, in: account, acknowledgement: "Archived") { client in
            try await client.archive(threadID: message.threadID)
        }
    }

    func delete(_ message: UnreadMessage, in account: GoogleAccount) async {
        await performMailAction(on: message, in: account, acknowledgement: "Moved to trash") { client in
            try await client.trash(threadID: message.threadID)
        }
    }

    func blockAndReportSpam(_ message: UnreadMessage, in account: GoogleAccount) async {
        await performMailAction(on: message, in: account, acknowledgement: "Blocked and reported as spam") { client in
            try await client.blockAndReportSpam(threadID: message.threadID, senderEmail: message.senderEmail)
        }
    }

    /// Unsubscribes in one click and archives the conversation if the sender supports it,
    /// otherwise opens the sender's unsubscribe page or a prefilled unsubscribe email in Gmail.
    func unsubscribe(from message: UnreadMessage, in account: GoogleAccount) async {
        switch message.unsubscribe {
        case .oneClick(let url):
            await performMailAction(on: message, in: account, acknowledgement: "Unsubscribed and archived") { client in
                try await unsubscribeWithOneClick(url)
                try await client.archive(threadID: message.threadID)
            }
        case .website(let url):
            NSWorkspace.shared.open(url)
        case .email(let mailto):
            NSWorkspace.shared.open(gmailComposeURL(for: mailto, accountEmail: account.email))
        case nil:
            break
        }
    }

    /// Runs `action`, then replaces the message's row with `acknowledgement` for a few seconds
    /// before removing it and refreshing to get the real unread count. If the action fails,
    /// the row stays and the error is shown.
    private func performMailAction(
        on message: UnreadMessage,
        in account: GoogleAccount,
        acknowledgement: String,
        _ action: (GmailClient) async throws -> Void
    ) async {
        account.pendingActions.insert(message.threadID)
        do {
            let token = try await validAccessToken(for: account)
            try await action(GmailClient(accessToken: token))
        } catch {
            account.pendingActions.remove(message.threadID)
            if let error = error as? GoogleAPIError, error.reason == "insufficientPermissions" {
                // Accounts added when the app could only read mail need to sign in again to allow changes.
                account.errorMessage = "No permission to change mail. Click Add Account and choose this account again to allow it."
            } else {
                account.errorMessage = error.localizedDescription
            }
            return
        }
        account.acknowledgements[message.threadID] = acknowledgement
        account.pendingActions.remove(message.threadID)
        try? await Task.sleep(for: Self.acknowledgementDuration)
        account.acknowledgements[message.threadID] = nil
        account.messages.removeAll { $0.threadID == message.threadID }
        await refresh(account)
    }

    /// The start of the message's text for the hover preview, fetched once per message. Nil if it couldn't be loaded.
    func preview(of message: UnreadMessage, in account: GoogleAccount) async -> String? {
        if let cached = previews[message.id] { return cached }
        do {
            let token = try await validAccessToken(for: account)
            let text = try await GmailClient(accessToken: token).bodyText(id: message.id)
            let preview = String(text.prefix(Self.previewLength))
            previews[message.id] = preview
            return preview
        } catch {
            return nil
        }
    }

    func open(_ message: UnreadMessage, in account: GoogleAccount) {
        NSWorkspace.shared.open(message.gmailURL(for: account.email))
    }

    func openInbox(of account: GoogleAccount) {
        NSWorkspace.shared.open(GmailClient.inboxURL(for: account.email))
    }

    func openCalendar(of account: GoogleAccount) {
        NSWorkspace.shared.open(CalendarClient.calendarURL(for: account.email))
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
    /// Messages that were just acted on (by thread ID), with the text shown in place of their row.
    fileprivate(set) var acknowledgements: [String: String] = [:]
    /// Messages (by thread ID) whose action is in progress, so their rows can show that instead of looking untouched.
    fileprivate(set) var pendingActions: Set<String> = []
    fileprivate(set) var unreadCount: Int?
    fileprivate(set) var isRefreshing = false
    /// Whether mail and events have been fetched at least once.
    fileprivate(set) var hasLoaded = false
    fileprivate(set) var errorMessage: String?
    fileprivate(set) var events: [CalendarEvent] = []
    fileprivate(set) var calendarErrorMessage: String?
    /// Whether the account's mail and events are shown in the menu.
    var isExpanded = true
    fileprivate var accessToken: AccessToken?

    var id: String { email }

    /// Events that haven't ended yet, soonest first.
    var upcomingEvents: [CalendarEvent] {
        let now = Date.now
        return events.filter { $0.end > now }
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
