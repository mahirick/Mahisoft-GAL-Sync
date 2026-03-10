# CLAUDE.md — Mahisoft GAL Sync macOS Menu Bar App

## Project Overview

Build a native macOS menu bar utility app called **Mahisoft GAL Sync** that syncs the Google Workspace Global Address List (GAL) for Mahisoft.com into a "Mahisoft GAL" group in Apple Contacts. The app targets macOS 14+ (Sonoma), is written entirely in Swift/SwiftUI, and is distributed as a signed/notarized .app bundle.

The user is a senior developer acting as PO — they will not write code. You write all code, tests, configs, and scripts. You have full autonomy. Do not ask for approval on file creation, structure decisions, or implementation details. Just build it.

---

## Permissions & Autonomy

You have blanket permission to:
- Create, modify, delete any files in this project
- Install dependencies via Swift Package Manager
- Create directories, restructure the project
- Run builds, tests, linting
- Make all architectural and implementation decisions
- Create signing configs, entitlements, Info.plist entries
- Generate assets (icons, etc.)

Do NOT ask for confirmation on any of the above. Just do it.

---

## Architecture

### Tech Stack
- **Language:** Swift 5.9+
- **UI:** SwiftUI with `MenuBarExtra` (persistent)
- **Minimum target:** macOS 14.0 (Sonoma)
- **Package manager:** Swift Package Manager (SPM)
- **Build system:** Xcode project (generate with `swift package generate-xcodeproj` or maintain Package.swift + Xcode workspace)

### App Type
- Menu bar only — no Dock icon (`LSUIElement = true` in Info.plist)
- Uses `MenuBarExtra` with `.window` style for the settings panel
- Runs as a background agent with periodic sync

### Dependencies (via SPM)
- **google-auth-library-swift** or **AppAuth-iOS** (OAuthSwift if needed) — Google OAuth 2.0
- **KeychainAccess** or native Security framework — secure token storage
- No Electron, no web views, no bridging to Node.js

---

## Features

### Menu Bar Icon & Dropdown
- SF Symbol icon in menu bar (e.g., `person.2.circle` or `arrow.triangle.2.circlepath`)
- Dropdown menu items:
  - **Sync Now** — triggers immediate sync
  - **Last synced: [timestamp]** — greyed out, informational
  - **Syncing...** with progress indicator (when active)
  - Separator
  - **Preferences...** — opens settings window
  - Separator
  - **Quit Mahisoft GAL Sync**

### Preferences Window
A proper SwiftUI settings window with tabs:

#### Tab 1: Accounts
- List of configured Google Workspace accounts
- **Add Account** button → triggers OAuth flow in system browser
- Each account row shows:
  - Email address
  - Domain (auto-detected from email)
  - Last sync status (success/fail/never)
  - **Remove** button
- OAuth scopes requested:
  - `https://www.googleapis.com/auth/admin.directory.user.readonly` (for admins — pulls full org directory)
  - `https://www.googleapis.com/auth/directory.readonly` (for non-admin users — pulls directory contacts they can see)
- The app should request `directory.readonly` first (works for all users). If the user is a Workspace admin and wants the full org list, offer an option to re-auth with `admin.directory.user.readonly`.

#### Tab 2: Sync Settings
- **Sync interval** picker: 1 hour, 4 hours, 12 hours, 24 hours (default: 4 hours)
- **Contact group name** — text field, default: "Company Directory"
  - All synced contacts go into this group in Apple Contacts
  - Separate group per domain (e.g., "Mahisoft GAL", "H3Y Directory") — toggle option
- **Remove contacts when deleted from directory** — checkbox, default: ON
- **Sync on launch** — checkbox, default: ON
- **Include suspended users** — checkbox, default: OFF
- **Include profile photos** — checkbox, default: ON

#### Tab 3: About
- App version
- Link to project repo (if applicable)
- "Made by Mahisoft" attribution

### Launch at Login
- Use `SMAppService.mainApp` (modern API, macOS 13+) for launch-at-login
- Toggle in Preferences → Sync Settings tab
- Default: ON (prompt user on first launch)

---

## Core Sync Logic

### Google Directory Fetch
1. For each configured account, call the appropriate Google API:
   - **Admin users:** `GET https://admin.googleapis.com/admin/directory/v1/users?domain={domain}&maxResults=500&projection=full`
   - **Non-admin users:** `GET https://people.googleapis.com/v1/people:listDirectoryPeople?readMask=names,emailAddresses,phoneNumbers,photos,organizations&sources=DIRECTORY_SOURCE_TYPE_DOMAIN_PROFILE&pageSize=1000`
2. Handle pagination (`nextPageToken` / `pageToken`)
3. Collect: full name, email(s), phone(s), title, department, photo URL, org unit path
4. Map to an internal `DirectoryPerson` model

### Apple Contacts Write
1. Use `CNContactStore` with appropriate authorization
   - Request access on first sync: `CNContactStore().requestAccess(for: .contacts)`
2. Find or create the target contact group (`CNGroup`) — match by name
3. For each `DirectoryPerson`:
   - Search existing contacts in the group by email (primary match key)
   - If exists → update fields that changed (don't overwrite user edits to notes/custom fields)
   - If new → create `CNMutableContact`, add to group
   - If removed from directory and "remove" setting is ON → remove from group (NOT delete the contact — just remove group membership)
4. Profile photos: download from Google, set as `imageData` on the contact
5. All writes via `CNSaveRequest` — batch where possible

### Conflict Handling
- Google directory is source of truth for: name, email, phone, title, department, photo
- Apple Contacts is source of truth for: notes, custom labels, any fields not in the directory
- Never overwrite fields that don't come from the directory

### Error Handling
- OAuth token expired → auto-refresh using refresh token. If refresh fails → mark account as "needs re-auth", show alert badge on menu bar icon
- Network failure → retry with exponential backoff (max 3 retries), then wait for next scheduled sync
- Contacts framework permission denied → show alert with instructions to enable in System Settings → Privacy → Contacts
- Partial sync failure → log failures, sync what you can, report count in status

---

## OAuth Flow

### Setup (user does this once in Google Cloud Console — document in README)
The app ships with a bundled OAuth client ID for a Google Cloud project. Users who want to use their own can override in Preferences.

### Default Bundled Config
- Include placeholder `client_id` and `redirect_uri` in a `GoogleOAuthConfig.plist` (or similar)
- Redirect URI: `com.mahisoft.directorysync:/oauth/callback` (custom URL scheme)
- Register the custom URL scheme in Info.plist

### Flow
1. User clicks "Add Account"
2. App opens system browser to Google OAuth consent screen
3. User authorizes → redirects back to app via custom URL scheme
4. App exchanges auth code for access + refresh tokens
5. Store tokens in macOS Keychain (use `SecItemAdd` / KeychainAccess library)
6. Determine if user is admin by attempting admin API call — if 403, fall back to People API

---

## Data Storage

- **Tokens:** macOS Keychain only. Never write tokens to UserDefaults or disk.
- **Preferences:** `UserDefaults.standard` (sync interval, group names, toggles)
- **Sync state:** `UserDefaults` or a small JSON file in Application Support
  - Last sync timestamp per account
  - Last known directory hash (to skip no-op syncs)
  - Per-contact last-modified tracking
- **App Support directory:** `~/Library/Application Support/com.mahisoft.MahisoftGALSync/`

---

## Entitlements & Signing

### Required Entitlements
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.personal-information.addressbook</key>
    <true/>
    <key>com.apple.security.keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)com.mahisoft.MahisoftGALSync</string>
    </array>
</dict>
</plist>
```

### Info.plist Keys
```xml
<key>LSUIElement</key>
<true/>
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>Google OAuth Callback</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.mahisoft.directorysync</string>
        </array>
    </dict>
</array>
<key>NSContactsUsageDescription</key>
<string>Mahisoft GAL Sync needs access to Contacts to sync your company directory.</string>
```

---

## Project Structure

```
MahisoftGALSync/
├── Package.swift (or MahisoftGALSync.xcodeproj)
├── Sources/
│   └── MahisoftGALSync/
│       ├── App/
│       │   ├── MahisoftGALSyncApp.swift          # @main, MenuBarExtra
│       │   └── AppDelegate.swift               # URL scheme handling
│       ├── Views/
│       │   ├── MenuBarView.swift               # Dropdown menu content
│       │   ├── PreferencesView.swift            # TabView container
│       │   ├── AccountsTab.swift               # Account management UI
│       │   ├── SyncSettingsTab.swift            # Sync config UI
│       │   └── AboutTab.swift
│       ├── Models/
│       │   ├── DirectoryPerson.swift            # Internal person model
│       │   ├── SyncAccount.swift                # Configured account model
│       │   └── SyncState.swift                  # Sync status/history
│       ├── Services/
│       │   ├── GoogleAuthService.swift          # OAuth flow + token management
│       │   ├── GoogleDirectoryService.swift     # API calls to fetch directory
│       │   ├── ContactsSyncService.swift        # CNContactStore read/write
│       │   ├── SyncOrchestrator.swift           # Scheduling + coordination
│       │   └── KeychainService.swift            # Secure token storage
│       ├── Utilities/
│       │   ├── Logger.swift                     # os.Logger wrapper
│       │   └── Constants.swift                  # Bundle IDs, API URLs, defaults
│       └── Resources/
│           ├── Assets.xcassets                  # App icon, menu bar icon
│           ├── GoogleOAuthConfig.plist          # Client ID, redirect URI
│           └── MahisoftGALSync.entitlements
├── Tests/
│   └── MahisoftGALSyncTests/
│       ├── GoogleDirectoryServiceTests.swift
│       └── ContactsSyncServiceTests.swift
└── README.md
```

---

## README.md Content

Generate a README that includes:

### For End Users (coworkers)
1. Download the .app from [distribution link]
2. Move to /Applications
3. Launch — it appears in your menu bar
4. Click the icon → Preferences → Add Account
5. Sign in with your Google Workspace account
6. Contacts will sync automatically

### For Admins (Rick)
1. Google Cloud Console setup:
   - Create project
   - Enable Admin SDK API + People API
   - Create OAuth 2.0 Client ID (macOS type)
   - Add redirect URI: `com.mahisoft.directorysync:/oauth/callback`
   - Configure OAuth consent screen (internal to org)
2. Update `GoogleOAuthConfig.plist` with your client ID
3. Build, sign, notarize, distribute

### Building
```bash
# Open in Xcode
open MahisoftGALSync.xcodeproj

# Or build from CLI
xcodebuild -scheme MahisoftGALSync -configuration Release
```

---

## Code Style & Conventions

- Use Swift concurrency (`async/await`, `Task`, `@MainActor`) — no completion handlers
- Use `os.Logger` for logging (subsystem: `com.mahisoft.MahisoftGALSync`)
- Use `@Observable` (macOS 14+) for state management, not `ObservableObject`
- Use `@AppStorage` for UserDefaults-backed preferences
- Error types: create a `MahisoftGALSyncError` enum conforming to `LocalizedError`
- No force unwraps. No `try!`. Handle errors properly.
- Use `actors` for thread-safe services where appropriate (e.g., `SyncOrchestrator`)

---

## Testing

- Unit tests for:
  - `DirectoryPerson` mapping from Google API JSON
  - Sync logic (mock `CNContactStore` with protocol)
  - Token refresh logic
  - Conflict resolution
- UI tests optional but nice to have for the preferences flow

---

## Build & Distribution

- Build as a Universal Binary (arm64 + x86_64) for compatibility
- Code sign with the Mahisoft Apple Developer Team
- Notarize for Gatekeeper
- Distribute as a .dmg or .zip — no App Store (to avoid review delays for internal tool)
- Include a simple `Makefile` or `build.sh` that does: build → sign → notarize → package

---

## Edge Cases to Handle

1. **User is not a Workspace admin** — fall back to People API directory listing (which shows contacts the user can see in their org's directory)
2. **Multiple domains** — user adds multiple accounts (one per domain). Each gets its own contact group.
3. **User removes an account** — remove all contacts from that domain's group (confirm with alert first)
4. **Contact exists outside the group** — if a directory person already exists in Apple Contacts but NOT in the managed group, do NOT modify them. Only manage contacts within the app's groups.
5. **Photo download failures** — skip photo, sync everything else, retry photo on next sync
6. **Rate limiting** — Google Admin SDK has per-user and per-domain limits. Implement exponential backoff.
7. **Very large orgs** — paginate correctly, don't load everything into memory at once
8. **Keychain access after OS update** — handle `-25293` (authorization denied) gracefully, prompt re-auth
9. **Contacts permission revoked** — detect on sync attempt, show clear instructions to re-enable
10. **App running but no accounts configured** — show a "Get Started" prompt in the menu dropdown