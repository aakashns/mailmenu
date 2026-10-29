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
                ErrorText(error, dismiss: { model.errorMessage = nil })
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

    var body: some View {
        // Grow with the content, and scroll once it gets too tall for the screen.
        HeightCap(maxHeight: 520) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.accounts) { account in
                        if account !== model.accounts.first {
                            Divider()
                        }
                        AccountSection(account: account)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// Sizes its content to its ideal height, up to `maxHeight`.
///
/// Measuring and sizing happen in the same layout pass. Reading the height with a geometry callback and then
/// setting a frame would lag a frame behind, briefly leaving a gap or clipping rows whenever the list changes.
private struct HeightCap: Layout {
    var maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        // A scroll view proposed no height reports the full height of what it contains.
        let ideal = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: ideal.width, height: min(ideal.height, maxHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

private struct AccountSection: View {
    @Environment(AppModel.self) private var model
    let account: GoogleAccount

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    account.isExpanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        // Only the chevron animates. The panel resizes at once, so animating the rows
                        // would leave them sliding around inside a window that's already its final size.
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(account.isExpanded ? 90 : 0))
                            .animation(.snappy(duration: 0.2), value: account.isExpanded)
                        Text(account.email)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let count = account.count(for: model.mailFilter), count > 0 {
                            Text(count, format: .number)
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: .capsule)
                                .fixedSize()
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(account.isExpanded ? "Collapse" : "Expand")
                Spacer()
                // The spinner takes the button's place in a fixed-size slot, so the header doesn't shift.
                ZStack {
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
                }
                .frame(width: 16, height: 16)
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

                if !account.visibleMessages.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(account.visibleMessages) { message in
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

/// An error in red, cut off after a few lines (hover for the rest), with an optional button to dismiss it.
private struct ErrorText: View {
    let message: String
    let dismiss: (() -> Void)?

    init(_ message: String, dismiss: (() -> Void)? = nil) {
        self.message = message
        self.dismiss = dismiss
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(message)
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .help("Dismiss")
            }
        }
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
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(.secondary.opacity(0.6), lineWidth: 1))
                        .contentShape(.circle)
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
