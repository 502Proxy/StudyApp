#!/bin/bash
# Erstellt ein Release: Archiv bauen, DMG erzeugen, Update-Feed (appcast.xml) signieren
# und – falls die GitHub-CLI angemeldet ist – die DMG hochladen.
#
#   scripts/release.sh --setup          # einmalig: Sparkle-Werkzeuge laden, Schlüssel erzeugen
#   scripts/release.sh 1.2              # Version 1.2, Build-Nummer = Zeitstempel
#   scripts/release.sh 1.2 --no-upload  # nur lokal bauen
#
# Release-Notizen (optional): docs/release-notes/<Version>.md, eine Zeile pro Punkt, z. B. „- PDF-Suche“.
set -euo pipefail

VERSION="${1:?Bitte Version angeben, z. B. scripts/release.sh 1.2}"
UPLOAD=true
[[ "${2:-}" == "--no-upload" ]] && UPLOAD=false

REPO="502Proxy/StudyApp"
# Alle DMGs liegen in einem festen GitHub-Release „updates“, damit jede Version eine stabile URL hat.
UPDATES_TAG="updates"
SPARKLE_VERSION="${SPARKLE_VERSION:-2.6.4}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build/release"
ARCHIVE="$BUILD_DIR/StudyApp.xcarchive"
UPDATES_DIR="$BUILD_DIR/updates"
SPARKLE_DIR="$ROOT/build/sparkle"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
DMG="$UPDATES_DIR/StudyApp-$VERSION.dmg"

cd "$ROOT"

download_sparkle() {
    if [[ ! -x "$SPARKLE_DIR/bin/generate_appcast" ]]; then
        echo "→ Lade Sparkle $SPARKLE_VERSION …"
        mkdir -p "$SPARKLE_DIR"
        curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
            | tar -xJ -C "$SPARKLE_DIR"
    fi
}

if [[ "$VERSION" == "--setup" ]]; then
    download_sparkle
    echo "→ Erzeuge bzw. zeige den Signierschlüssel (privater Teil bleibt im Schlüsselbund) …"
    "$SPARKLE_DIR/bin/generate_keys"
    echo "✓ Den angezeigten öffentlichen Schlüssel in Config/Info.plist bei SUPublicEDKey eintragen."
    exit 0
fi

if grep -q "HIER_DEN_PUBLIC_KEY_EINTRAGEN" Config/Info.plist; then
    echo "✗ In Config/Info.plist fehlt noch der öffentliche Schlüssel (SUPublicEDKey). Siehe docs/RELEASING.md." >&2
    exit 1
fi

# 1. Sparkle-Werkzeuge (generate_appcast) einmalig herunterladen
download_sparkle

# 2. Archiv bauen
echo "→ Baue StudyApp $VERSION ($BUILD_NUMBER) …"
rm -rf "$ARCHIVE"
xcodebuild -project StudyApp.xcodeproj -scheme StudyApp -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    archive -quiet

APP="$ARCHIVE/Products/Applications/StudyApp.app"
[[ -d "$APP" ]] || { echo "✗ StudyApp.app wurde nicht gefunden: $APP" >&2; exit 1; }

# Startet die App überhaupt? dyld lädt Sparkle nur bei gleicher Team-ID oder abgeschalteter Library Validation.
team_id() { codesign -dv "$1" 2>&1 | sed -n 's/^TeamIdentifier=//p'; }
SPARKLE_FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE_FRAMEWORK" && "$(team_id "$APP")" != "$(team_id "$SPARKLE_FRAMEWORK")" ]] \
    && ! codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "disable-library-validation"; then
    echo "✗ App und Sparkle.framework haben verschiedene Team-IDs – die App würde beim Start abstürzen." >&2
    echo "  Entitlement com.apple.security.cs.disable-library-validation fehlt (Config/StudyApp.entitlements)." >&2
    exit 1
fi

# 3. DMG mit Verknüpfung auf „Programme“
echo "→ Erzeuge $(basename "$DMG") …"
mkdir -p "$UPDATES_DIR"
STAGING="$BUILD_DIR/dmg"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Programme"
hdiutil create -volname "StudyApp" -srcfolder "$STAGING" -ov -format UDZO "$DMG" -quiet
rm -rf "$STAGING"

# 4. Release-Notizen als HTML neben die DMG legen (generate_appcast übernimmt sie)
NOTES="$ROOT/docs/release-notes/$VERSION.md"
if [[ -f "$NOTES" ]]; then
    {
        echo "<ul>"
        sed -n 's/^[-*] \(.*\)$/<li>\1<\/li>/p' "$NOTES"
        echo "</ul>"
    } > "${DMG%.dmg}.html"
fi

# 5. Update-Feed erzeugen und mit dem privaten Schlüssel aus dem Schlüsselbund signieren
echo "→ Aktualisiere docs/appcast.xml …"
"$SPARKLE_DIR/bin/generate_appcast" \
    --download-url-prefix "https://github.com/$REPO/releases/download/$UPDATES_TAG/" \
    -o "$ROOT/docs/appcast.xml" \
    "$UPDATES_DIR"

# 6. Hochladen (optional, braucht `gh auth login`)
if $UPLOAD && command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
    echo "→ Lade DMG zu GitHub hoch …"
    gh release view "$UPDATES_TAG" --repo "$REPO" >/dev/null 2>&1 \
        || gh release create "$UPDATES_TAG" --repo "$REPO" --title "Updates" --notes "Downloads für automatische Updates."
    gh release upload "$UPDATES_TAG" "$DMG" --repo "$REPO" --clobber
    echo "✓ Hochgeladen. Jetzt docs/appcast.xml committen und pushen:"
    echo "    git add docs/appcast.xml && git commit -m \"chore(release): ${VERSION}\" && git push"
else
    echo "✓ Fertig: $DMG"
    echo "  Noch zu tun (GitHub-CLI nicht angemeldet):"
    echo "    1. Auf https://github.com/${REPO}/releases das Release mit dem Tag „${UPDATES_TAG}“ öffnen"
    echo "       (beim ersten Mal anlegen) und $(basename "$DMG") hochladen."
    echo "    2. git add docs/appcast.xml && git commit -m \"chore(release): ${VERSION}\" && git push"
fi
