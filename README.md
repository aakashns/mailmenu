# Mail Menu

A macOS menu bar app to track unread email and upcoming calendar events.

Currently: sign in with Google and see the unread messages in your Gmail inbox. Click a message to open it in Gmail in your default browser.

## Repository layout

```
app/        macOS app (SwiftUI, Xcode project)
  Config/   build settings, Info.plist, entitlements
  MailMenu/ Swift sources
```

## Development setup

Requirements: macOS 14+, Xcode 16+.

### 1. Create a Google OAuth client

1. Go to the [Google Cloud console](https://console.cloud.google.com/) and create a project (e.g. "Mail Menu").
2. Enable the [Gmail API](https://console.cloud.google.com/apis/library/gmail.googleapis.com) for the project.
3. Open [Google Auth Platform](https://console.cloud.google.com/auth/overview) and click **Get started**:
   - App name: `Mail Menu`, plus your email as the support email.
   - Audience: **External**.
4. Under **Audience → Test users**, add the Google account(s) you want to sign in with.
5. Under **Data Access**, add the scope `https://www.googleapis.com/auth/gmail.readonly`.
6. Under **Clients**, click **Create client**:
   - Application type: **iOS** (Google uses iOS clients for macOS apps; they need no client secret)
   - Bundle ID: `app.mailmenu.MailMenu`
7. Copy the client ID (it looks like `1234567890-abc…xyz.apps.googleusercontent.com`).

### 2. Configure and run the app

```sh
cp app/Config/Local.xcconfig.example app/Config/Local.xcconfig
# edit app/Config/Local.xcconfig and set GOOGLE_CLIENT_ID
open app/MailMenu.xcodeproj
```

Press **⌘R** in Xcode. An envelope icon appears in the menu bar (there's no Dock icon). Click it, then click **Continue with Google**.

To build and run from the terminal instead, run this from the repository root:

```sh
xcodebuild -project app/MailMenu.xcodeproj -scheme MailMenu -configuration Debug -derivedDataPath app/build -quiet \
  && { pkill -x MailMenu; open app/build/Build/Products/Debug/MailMenu.app; }
```

The command quits any running copy of the app before opening the new build. If the build fails, the old copy keeps running.

### Things to know while developing

- **Google warns that the app isn't verified.** That's expected while the Google Cloud app is in Testing mode. Click **Continue**.
- **You'll be signed out after 7 days.** Google expires refresh tokens after 7 days for apps in Testing mode. Sign in again when it happens.
- **macOS asks for Keychain access after each rebuild.** The default ad-hoc signature changes with every build. To avoid the prompt, set `DEVELOPMENT_TEAM` in `Local.xcconfig` (a free Apple ID personal team works).

## How it works

- **Sign-in** uses OAuth 2.0 for native apps (authorization code + PKCE) through `ASWebAuthenticationSession`. The refresh token is stored in the macOS Keychain. Nothing leaves your Mac except requests to Google.
- **Mail** is read through the Gmail REST API with the read-only `gmail.readonly` scope. The app lists messages labeled both `INBOX` and `UNREAD`.

## License

[MIT](LICENSE)
