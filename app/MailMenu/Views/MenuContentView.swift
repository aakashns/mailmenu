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
                        if let count = account.count(for: model.mailFilter), count > 0 {
                            Text(count, format: .number)
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
                if account.isRefreshing {
                    ProgressView().controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Button {
                        Task { await model.refresh(account) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 16, height: 16)
                    }
                    .help("Refresh")
                }
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
                                snooze: { date in Task { await model.snooze(message, until: date, in: account) } },
                                delete: { Task { await model.delete(message, in: account) } },
                                unsubscribe: { Task { await model.unsubscribe(from: message, in: account) } },
                                blockAndReportSpam: { Task { await model.blockAndReportSpam(message, in: account) } },
                                loadPreview: { await model.preview(of: message, in: account) },
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
                            EventRow(event: event, action: { model.open(event) }, openInCalendar: { model.openInCalendar(event) })
                        }
                    }
                    .padding([.horizontal, .bottom], 4)
                }

                if account.hasLoaded, account.messages.isEmpty, account.upcomingEvents.isEmpty,
                   account.errorMessage == nil, account.calendarErrorMessage == nil {
                    Text(model.mailFilter == .unread ? "No unread mail or upcoming events." : "No mail or upcoming events.")
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

/// Progress of the latest mail action, shown in the footer.
private struct StatusLine: View {
    let status: ActionStatus

    var body: some View {
        HStack(spacing: 6) {
            if status.isWorking {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Text(status.text)
                .foregroundStyle(status.isWorking ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
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
        @Bindable var model = model
        HStack(spacing: 10) {
            // The status replaces the selector in place (which stays in the layout, hidden), so the footer doesn't change size.
            ZStack(alignment: .leading) {
                if !model.accounts.isEmpty {
                    Picker("Show", selection: $model.mailFilter) {
                        ForEach(MailFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .opacity(model.status == nil ? 1 : 0)
                    .allowsHitTesting(model.status == nil)
                }
                if let status = model.status {
                    StatusLine(status: status)
                }
            }
            Spacer()
            if !model.accounts.isEmpty {
                Button {
                    Task { await model.addAccount() }
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(model.isSigningIn)
                .help("Add account")
            }
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .help("Quit Mail Menu")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
