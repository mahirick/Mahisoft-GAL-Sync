# Mahisoft GAL Sync

A native macOS menu bar app that syncs the Google Workspace Global Address List (GAL) for Mahisoft.com into a "Mahisoft GAL" group in Apple Contacts. Built with Swift/SwiftUI, targeting macOS 14+ (Sonoma).

No Electron, no web views — just a lightweight menu bar agent that keeps your company directory up to date in Apple Contacts automatically.

---

## Quick Start (End Users)

1. Download `Mahisoft GAL Sync.app`
2. Move to `/Applications`
3. Launch — a dark blue people icon appears in your menu bar
4. Click the icon → **Preferences** → **Add Account**
5. Sign in with your Google Workspace account in the browser
6. Contacts sync automatically on a schedule (default: every 4 hours)

Your coworkers will appear in Apple Contacts under a **"Mahisoft GAL"** group, with names, emails, phones, titles, and photos kept up to date.

---

## Features

- **Automatic sync** — runs on a configurable schedule (1h / 4h / 12h / 24h)
- **Sync Now** — trigger an immediate sync from the menu bar or Preferences
- **Multiple accounts** — add multiple Google Workspace accounts, each with its own contact group
- **Smart updates** — detects directory changes via hashing; skips no-op syncs
- **Profile photos** — downloads and sets Google profile photos on contacts
- **Activity Log** — full log of sync operations, errors, and OAuth events
- **How It Works** — built-in guide explaining the app's purpose and process
- **Update notifications** — checks for new versions automatically (once per 24 hours)
- **Launch at login** — starts silently on macOS login via `SMAppService`
- **Privacy-first** — tokens in Keychain only, read-only Google access, contacts managed in a dedicated group

---

## Google Cloud Setup (Admin — One-Time)

The app requires OAuth 2.0 credentials from a Google Cloud project. This is done once by the admin distributing the app.

### 1. Create a Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project (e.g., "Mahisoft GAL Sync")
3. Select the project

### 2. Enable APIs

Navigate to **APIs & Services → Library** and enable:

- **Admin SDK API** — for admin users to pull the full org directory
- **People API** — for non-admin users to pull directory contacts they can see

### 3. Configure OAuth Consent Screen

1. Go to **APIs & Services → OAuth consent screen**
2. Choose **Internal** (restricts to your Workspace org — no Google review needed)
3. Fill in:
   - App name: `Mahisoft GAL Sync`
   - User support email: your admin email
   - Authorized domains: your domain
4. Add scopes:
   - `https://www.googleapis.com/auth/directory.readonly`
   - `https://www.googleapis.com/auth/admin.directory.user.readonly`
   - `email`, `profile`
5. Save

### 4. Create OAuth Client ID

1. Go to **APIs & Services → Credentials**
2. Click **Create Credentials → OAuth client ID**
3. Application type: **Desktop app**
4. Name: `Mahisoft GAL Sync`
5. Click **Create**
6. Copy the **Client ID** and **Client Secret**

> **Note:** The app uses a loopback HTTP server (`http://127.0.0.1:{port}`) to receive the OAuth callback. Google Desktop clients allow loopback redirect URIs automatically — no explicit redirect URI configuration is needed.

### 5. Configure the App

Copy the example secrets file and add your credentials:

```bash
cp MahisoftGALSync/Sources/Resources/Secrets.plist.example \
   MahisoftGALSync/Sources/Resources/Secrets.plist
```

Edit `Secrets.plist` and fill in both values:

```xml
<key>GOOGLE_CLIENT_ID</key>
<string>YOUR_CLIENT_ID.apps.googleusercontent.com</string>
<key>GOOGLE_CLIENT_SECRET</key>
<string>YOUR_CLIENT_SECRET</string>
```

> `Secrets.plist` is gitignored — it will never be committed. The checked-in `Secrets.plist.example` serves as a template.

---

## Building

### Prerequisites

- macOS 14.0+ (Sonoma)
- Xcode 15.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Build from Command Line

```bash
cd MahisoftGALSync
xcodegen generate
xcodebuild -project MahisoftGALSync.xcodeproj \
  -scheme MahisoftGALSync \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

### Build in Xcode

```bash
cd MahisoftGALSync
xcodegen generate
open MahisoftGALSync.xcodeproj
```

Then press **Cmd+R** to build and run.

### Run Tests

```bash
xcodebuild -project MahisoftGALSync.xcodeproj \
  -scheme MahisoftGALSyncTests \
  -configuration Debug \
  -destination 'platform=macOS' \
  test
```

---

## How It Works

1. **Connect** — Sign in with your Google Workspace account. The app opens your browser for a secure Google sign-in and receives the callback on a local loopback server. It never sees your password.
2. **Fetch** — The app calls the Google People API (or Admin SDK for workspace admins) to download the Mahisoft.com Global Address List — names, emails, phones, titles, departments, and photos.
3. **Sync** — Each person is matched by email in Apple Contacts. New people are added, changes are updated, and removed employees are cleaned up. All contacts go into the **"Mahisoft GAL"** group.
4. **Stay current** — The app syncs on a schedule (default: every 4 hours). It detects changes so unchanged directories are skipped. Hit **Sync Now** anytime from the menu bar.

### OAuth Flow (Loopback + PKCE)

```
┌──────────────────┐
│ Mahisoft GAL      │  1. Start loopback HTTP server on 127.0.0.1:{random port}
│ Sync (macOS app)  │  2. Generate PKCE code_verifier + SHA256 challenge
│                   │  3. Open browser with challenge + redirect to loopback
│                   │─────────────────────────►┌──────────────────┐
│                   │                           │  Google OAuth     │
│                   │◄─────────────────────────│  (browser)        │
│                   │  4. Browser redirects to  └──────────────────┘
│                   │     http://127.0.0.1:{port}?code=...
│                   │
│                   │  5. Exchange code + verifier + client_secret for tokens
│                   │─────────────────────────►┌──────────────────┐
│                   │                           │  Google Token     │
│                   │◄─────────────────────────│  Endpoint         │
│                   │  6. Receive access_token  └──────────────────┘
│                   │     + refresh_token
│                   │
│                   │  7. Store tokens in macOS Keychain
└──────────────────┘
```

> Google Desktop OAuth clients require `client_secret` for token exchange, even when using PKCE. The loopback server uses POSIX sockets to work reliably inside the App Sandbox.

### Sync Logic

- Google directory is **source of truth** for: name, email, phone, title, department, photo
- Apple Contacts is **source of truth** for: notes, custom labels, non-directory fields
- Contacts are matched by email address (primary key)
- Deleted contacts are removed from the managed group only — the contact itself is never deleted
- A SHA256 hash of directory contents is stored to skip no-op syncs

---

## Configuration

### Sync Settings (Preferences → Settings)

| Setting | Default | Description |
|---------|---------|-------------|
| Sync interval | 4 hours | How often to sync (1h, 4h, 12h, 24h) |
| Sync on launch | ON | Sync immediately when app starts |
| Launch at login | ON | Start automatically on macOS login |
| Contact group name | "Mahisoft GAL" | Name of the group in Apple Contacts |
| Separate group per domain | OFF | Create per-domain groups |
| Remove deleted contacts | ON | Remove from group when removed from directory |
| Include suspended users | OFF | Sync users with suspended Google accounts |
| Include profile photos | ON | Download and set Google profile photos |

### Data Storage

| Data | Location |
|------|----------|
| OAuth tokens | macOS Keychain |
| Preferences | `UserDefaults.standard` |
| Account list | `~/Library/Application Support/com.mahisoft.MahisoftGALSync/accounts.json` |
| Sync state | `~/Library/Application Support/com.mahisoft.MahisoftGALSync/sync_state.json` |
| Activity log | `~/Library/Application Support/com.mahisoft.MahisoftGALSync/activity_log.json` |

---

## Update Notifications

The app checks for updates automatically once per 24 hours (and on-demand via **Check for Updates** in the menu). It fetches a JSON manifest from a remote URL and compares semantic versions.

### Hosting the Update Manifest

Host a JSON file at the URL configured in `UpdateChecker.swift` (default: `https://raw.githubusercontent.com/mahirick/Mahisoft-GAL-Sync/main/update.json`). Format:

```json
{
  "version": "1.1.0",
  "build": "2",
  "downloadURL": "https://example.com/MahisoftGALSync.dmg",
  "releaseNotes": "Bug fixes and performance improvements."
}
```

When a newer version is detected, the menu bar shows an **"Update Available: v1.1.0"** button that opens the download page.

---

## Distribution

### Build for Release

```bash
cd MahisoftGALSync
xcodegen generate

# Archive
xcodebuild -project MahisoftGALSync.xcodeproj \
  -scheme MahisoftGALSync \
  -configuration Release \
  -archivePath build/MahisoftGALSync.xcarchive \
  archive

# Export (requires Developer ID Application certificate)
xcodebuild -exportArchive \
  -archivePath build/MahisoftGALSync.xcarchive \
  -exportPath build/ \
  -exportOptionsPlist ExportOptions.plist
```

### Using build.sh

A convenience script is included:

```bash
cd MahisoftGALSync
./build.sh                  # Full build → sign → notarize → DMG
./build.sh --skip-notarize  # Skip notarization (for testing)
```

### Requirements

- **Apple Developer Team** signing identity
- **Developer ID Application** certificate (for distribution outside the App Store)
- **Notarization** for Gatekeeper (handled by `build.sh`)
- Distribute as `.dmg` or `.zip` — no App Store needed for internal tools

### Entitlements

| Entitlement | Purpose |
|-------------|---------|
| `app-sandbox` | Required for notarization |
| `network.client` | Outbound HTTPS to Google APIs |
| `network.server` | Loopback server for OAuth callback |
| `personal-information.addressbook` | Apple Contacts read/write |
| `keychain-access-groups` | Secure OAuth token storage |

---

## Architecture

### Tech Stack

| Component | Technology |
|-----------|-----------|
| Language | Swift 5.9+ |
| UI | SwiftUI with `MenuBarExtra` |
| Min target | macOS 14.0 (Sonoma) |
| Auth | OAuth 2.0 with PKCE + client_secret (Desktop) |
| OAuth callback | Loopback HTTP server (POSIX sockets) |
| Token storage | macOS Keychain |
| Contacts | `CNContactStore` (Contacts framework) |
| Preferences | `@AppStorage` / `UserDefaults` |
| Logging | `os.Logger` + in-app `LogStore` |
| Dependencies | KeychainAccess (via SPM) |

### Project Structure

```
MahisoftGALSync/
├── project.yml                          # XcodeGen project definition
├── build.sh                             # Build, sign, notarize, package
├── Sources/
│   ├── App/
│   │   ├── MahisoftGALSyncApp.swift       # @main, MenuBarExtra, window scenes
│   │   └── AppDelegate.swift            # App lifecycle, contacts prompt
│   ├── Views/
│   │   ├── MenuBarView.swift            # Menu bar dropdown
│   │   ├── PreferencesView.swift        # Tabbed preferences window
│   │   ├── AccountsTab.swift            # Account management + Sync Now
│   │   ├── SyncSettingsTab.swift        # Sync configuration
│   │   ├── HowItWorksTab.swift          # How It Works guide
│   │   ├── AboutTab.swift               # App info
│   │   └── LogView.swift                # Activity log viewer
│   ├── Models/
│   │   ├── DirectoryPerson.swift        # Person model + Google API parsing
│   │   ├── SyncAccount.swift            # Account model + persistence
│   │   ├── SyncState.swift              # Sync timestamps + change hashes
│   │   └── MahisoftGALSyncError.swift     # Error types
│   ├── Services/
│   │   ├── GoogleAuthService.swift      # OAuth flow + token refresh
│   │   ├── OAuthCallbackServer.swift    # Loopback HTTP server (POSIX sockets)
│   │   ├── GoogleDirectoryService.swift # Admin API + People API fetching
│   │   ├── ContactsSyncService.swift    # Apple Contacts read/write
│   │   ├── SyncOrchestrator.swift       # Scheduling + coordination
│   │   ├── KeychainService.swift        # Secure token storage
│   │   ├── UpdateChecker.swift          # Version check + update notification
│   │   └── LogStore.swift               # Persistent activity log
│   ├── Utilities/
│   │   ├── Constants.swift              # Config, URLs, defaults
│   │   └── Logger.swift                 # os.Logger extensions
│   └── Resources/
│       ├── Assets.xcassets              # App icon
│       ├── GoogleOAuthConfig.plist      # Redirect URI, endpoints
│       ├── Secrets.plist                # Client ID + Secret (gitignored)
│       ├── Secrets.plist.example        # Template for collaborators
│       ├── Info.plist                   # URL scheme, permissions
│       └── MahisoftGALSync.entitlements   # Sandbox, network, contacts, keychain
└── Tests/
    └── MahisoftGALSyncTests/
        ├── DirectoryPersonTests.swift   # Model parsing tests
        └── SyncAccountTests.swift       # Account model tests
```

### Error Handling

Every error is caught, logged to both `os.Logger` (viewable in Console.app) and the in-app Activity Log, and surfaced to the user via the menu bar status.

| Scenario | Behavior |
|----------|----------|
| Token expired | Auto-refresh via refresh token |
| Refresh fails | Mark account "needs re-auth", show warning in menu |
| Admin API 403 | Automatic fallback to People API |
| Network failure | Exponential backoff retry (3 attempts), then wait for next sync |
| Contacts permission revoked | Error logged with instructions to re-enable |
| Partial sync failure | Log failures, sync what we can, report count |

---

## Credits

Made by **Mahisoft**
