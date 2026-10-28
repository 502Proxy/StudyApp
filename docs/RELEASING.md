# Releasing and automatic updates

StudyApp updates itself with [Sparkle](https://sparkle-project.org). The app checks the feed `https://502proxy.github.io/StudyApp/appcast.xml` daily, shows the release notes of a new version, downloads the DMG, replaces the app in `/Applications` and relaunches. Everything is free: Sparkle is open source, DMGs live in the GitHub release `updates`, the feed is served by GitHub Pages from `docs/`.

User data lives in the app container and survives updates.

## One-time setup

1. **Sparkle tools and keys:** `scripts/release.sh --setup` downloads the Sparkle tools to `build/sparkle` and creates the EdDSA key pair. The private key stays in your login keychain; the public key is printed.
   **Never share the private key** – without it no further update can be signed. Back it up with `build/sparkle/bin/generate_keys -x private-key.txt` and keep that file outside the repository.
2. **Public key:** put it into `Config/Info.plist` under `SUPublicEDKey`.
3. **GitHub Pages:** *Settings → Pages* → branch `main`, folder `/docs` (the repository must be public).
4. **GitHub CLI (optional):** `brew install gh` and `gh auth login`; the release script then uploads the DMG itself.

## Publishing a release

```bash
git switch main && git pull origin main
$EDITOR docs/release-notes/1.11.md     # one line per change: "- …"
scripts/qa.sh release-check
scripts/release.sh 1.11
git add docs/appcast.xml docs/release-notes/1.11.md CHANGELOG.md
git commit -m "chore(release): 1.11"
git push
```

Afterwards close the milestone `1.11` on GitHub and move its open issues to the next milestone.

`release.sh <version>`:

1. archives the Release build with the given version and a timestamp build number,
2. aborts if the app icon is missing or Sparkle could not load (team ID mismatch without the library-validation entitlement),
3. creates `build/release/updates/StudyApp-<version>.dmg` with a link to `/Applications`,
4. turns the release notes into HTML and signs the DMG while regenerating `docs/appcast.xml`,
5. uploads the DMG to the `updates` release (if `gh` is signed in; otherwise it prints the manual steps).

Keep `build/release/updates/` – `generate_appcast` builds the feed (and delta updates) from all DMGs in it. Also add the version to [CHANGELOG.md](../CHANGELOG.md).

## Without a paid Apple Developer account

- The app is signed ad hoc. The first installation from a DMG needs *right-click → Open* (or *System Settings → Privacy & Security → Open Anyway*).
- `generate_appcast` warns about a code-signing identity mismatch between versions. That is expected for ad-hoc builds; Sparkle accepts the update because the EdDSA signature is valid.
- macOS may ask once per update whether StudyApp may access its keychain item (Stud.IP sign-in). Choose „Always Allow“.
- Test every update on your own Mac first: install the previous version, then use „Nach Updates suchen …“.
