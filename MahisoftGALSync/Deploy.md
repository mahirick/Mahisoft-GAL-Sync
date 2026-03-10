# Deploying a New Version of Mahisoft GAL Sync

## Prerequisites (One-Time Setup)

- Developer ID Application certificate installed in Keychain
- Notarization credentials stored: `xcrun notarytool store-credentials "MahisoftGALSync" --apple-id "you@mahisoft.com" --team-id "XXXXXXXXXX" --password "xxxx-xxxx-xxxx-xxxx"`
- `xcodegen` installed: `brew install xcodegen`

---

## Release Steps

### 1. Bump the Version

Edit [project.yml](project.yml) and update `MARKETING_VERSION`:

```yaml
MARKETING_VERSION: 1.2.0   # ← change this
CURRENT_PROJECT_VERSION: 3  # ← also increment this (build number)
```

### 2. Update the Changelog

Add a summary of changes to [README.md](README.md) under a `## Changelog` section.

### 3. Build, Sign, Notarize, and Package

```bash
cd MahisoftGALSync
./build.sh
```

This runs the full pipeline:
- Generates Xcode project via XcodeGen
- Builds universal binary (arm64 + x86_64) in Release configuration
- Signs with Developer ID Application certificate
- Submits to Apple for notarization
- Staples the notarization ticket
- Packages into `build/MahisoftGALSync.dmg`

**Skip notarization for local testing only:**
```bash
./build.sh --skip-notarize
```

### 4. Verify the Build

```bash
# Confirm signing
codesign -dv --verbose=4 "build/Mahisoft GAL Sync.app"

# Confirm notarization is stapled (should say "accepted / source=Notarized Developer ID")
spctl -a -vv "build/Mahisoft GAL Sync.app"
```

### 5. Publish a GitHub Release

```bash
VERSION="v1.2.0"

# Tag the commit
git tag $VERSION
git push origin $VERSION

# Create GitHub release and attach the DMG
gh release create $VERSION build/MahisoftGALSync.dmg \
  --title "Mahisoft GAL Sync $VERSION" \
  --notes "See README.md for changelog."
```

The DMG download URL will be:
```
https://github.com/mahirick/Mahisoft-GAL-Sync/releases/download/v1.2.0/MahisoftGALSync.dmg
```

### 6. Update the Auto-Update Manifest

Edit `update.json` in the root of the repo:

```json
{
  "version": "1.2.0",
  "url": "https://github.com/mahirick/Mahisoft-GAL-Sync/releases/download/v1.2.0/MahisoftGALSync.dmg",
  "releaseNotes": "Brief description of what changed."
}
```

Commit and push:

```bash
git add update.json
git commit -m "chore: update manifest to v1.2.0"
git push origin main
```

Users running the current version will be notified of the update on their next check.

### 7. Notify the Team

Share the GitHub release link (or the direct DMG download URL) via Slack/email.

---

## Rollback

If a release has a critical bug, delete the GitHub release and re-tag the previous version:

```bash
gh release delete v1.2.0 --yes
git tag -d v1.2.0
git push origin :refs/tags/v1.2.0

# Restore previous version in update.json and push
```

---

## Version Numbering

Follow semantic versioning (`MAJOR.MINOR.PATCH`):

| Change | Example |
|--------|---------|
| Bug fix | 1.0.0 → 1.0.1 |
| New feature, backwards compatible | 1.0.0 → 1.1.0 |
| Breaking change or major milestone | 1.0.0 → 2.0.0 |

Always increment `CURRENT_PROJECT_VERSION` (build number) with every release, even patch releases.
