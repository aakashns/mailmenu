import SwiftUI

/// The panel shown when clicking the menu bar icon.
struct MenuContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if model.oauthConfig == nil {
                NotConfiguredView()
            } else if let account = model.account {
                SignedInView(email: account.email)
            } else {
                SignInView()
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
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
                Task { await model.signIn() }
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

private struct SignedInView: View {
    @Environment(AppModel.self) private var model
    let email: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(email)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if model.messages.isEmpty {
                Text(model.lastRefreshed == nil ? "Loading…" : "No unread mail")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.messages) { message in
                            MessageRow(message: message) { model.open(message) }
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 420)
            }
        }
        // Refresh every time the panel opens.
        .onAppear { Task { await model.refresh() } }
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
            if model.account != nil {
                Button("Sign Out") { model.signOut() }
            }
            Spacer()
            Button("Quit Mail Menu") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
