import SwiftUI

/// The panel shown when clicking the menu bar icon.
struct MenuContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if model.oauthConfig == nil {
                NotConfiguredView()
            } else if model.accounts.isEmpty {
                SignInView()
            } else {
                MainListView()
            }

            if let error = model.errorMessage {
                ErrorText(error)
            }

            Divider()
            FooterView()
        }
        .frame(width: 360)
    }
}

private struct SignInView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "envelope")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Sign in to see your unread mail")
                .foregroundStyle(.secondary)
            Button {
                Task { await model.addAccount() }
            } label: {
                Text("Continue with Google")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(model.isSigningIn)
        }
        .padding(20)
    }
}

/// Each account's unread mail and upcoming events.
private struct MainListView: View {
    @Environment(AppModel.self) private var model
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(model.accounts) { account in
                    if account !== model.accounts.first {
                        Divider()
                    }
                    AccountSection(account: account)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        // Grow with the content, and scroll once it gets too tall for the screen.
        .frame(height: min(contentHeight, 520))
        // Refresh every time the panel opens.
        .onAppear { Task { await model.refreshAll() } }
    }
}

private struct AccountSection: View {
    @Environment(AppModel.self) private var model
    let account: GoogleAccount

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { account.isExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(account.isExpanded ? 90 : 0))
                        Text(account.email)
                            .font(.headline)
                            .lineLimit(1)
                        if let unreadCount = account.unreadCount, unreadCount > 0 {
                            Text(unreadCount, format: .number)
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: .capsule)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(account.isExpanded ? "Collapse" : "Expand")
                Spacer()
                Button {
                    model.openInbox(of: account)
                } label: {
                    Image(systemName: "envelope")
                }
                .help("Open inbox in browser")
                Button {
                    model.openCalendar(of: account)
                } label: {
                    Image(systemName: "calendar")
                }
                .help("Open calendar in browser")
                if account.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await model.refresh(account) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh")
                }
                Button {
                    model.signOut(account)
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .help("Sign out of \(account.email)")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if account.isExpanded {
                if let error = account.errorMessage {
                    ErrorText(error)
                }

                if !account.messages.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(account.messages) { message in
                            MessageRow(
                                message: message,
                                archive: { Task { await model.archive(message, in: account) } },
                                unsubscribe: { Task { await model.unsubscribe(from: message, in: account) } },
                                blockAndReportSpam: { Task { await model.blockAndReportSpam(message, in: account) } },
                                open: { model.open(message, in: account) }
                            )
                        }
                    }
                    .padding([.horizontal, .bottom], 4)
                }

                if let error = account.calendarErrorMessage {
                    ErrorText(error)
                }

                if !account.upcomingEvents.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(account.upcomingEvents) { event in
                            EventRow(event: event) { model.open(event) }
                        }
                    }
                    .padding([.horizontal, .bottom], 4)
                }

                if account.hasLoaded, account.messages.isEmpty, account.upcomingEvents.isEmpty,
                   account.errorMessage == nil, account.calendarErrorMessage == nil {
                    Text("No unread mail or upcoming events.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
            }
        }
    }
}

private struct ErrorText: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
}

private struct NotConfiguredView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Google client ID not configured")
                .font(.headline)
            Text("Set GOOGLE_CLIENT_ID in app/Config/Local.xcconfig and rebuild. See the README for details.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
}

private struct FooterView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            if !model.accounts.isEmpty {
                Button("Add Account") {
                    Task { await model.addAccount() }
                }
                .disabled(model.isSigningIn)
            }
            Spacer()
            Button("Quit Mail Menu") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
