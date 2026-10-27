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
                Text(account.email)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
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

            if let error = account.errorMessage {
                ErrorText(error)
            }

            if account.messages.isEmpty {
                PlaceholderText(account.lastRefreshed == nil ? "Loading…" : "No unread mail")
            } else {
                VStack(spacing: 0) {
                    ForEach(account.messages) { message in
                        MessageRow(message: message) { model.open(message, in: account) }
                    }
                }
                .padding([.horizontal, .bottom], 4)
            }

            Text("Upcoming")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            if let error = account.calendarErrorMessage {
                ErrorText(error)
            }

            if account.upcomingEvents.isEmpty {
                if account.calendarErrorMessage == nil {
                    PlaceholderText(account.events == nil ? "Loading…" : "No events in the next 24 hours")
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(account.upcomingEvents) { event in
                        EventRow(event: event) { model.open(event) }
                    }
                }
                .padding([.horizontal, .bottom], 4)
            }
        }
    }
}

private struct PlaceholderText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
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
