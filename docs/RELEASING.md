# Releases und automatische Updates

StudyApp aktualisiert sich über [Sparkle](https://sparkle-project.org) selbst: Die App prüft täglich den
Update-Feed `https://502proxy.github.io/StudyApp/appcast.xml`, zeigt bei einer neuen Version ein Fenster mit
den Änderungen, lädt die DMG, ersetzt die alte App in „Programme“ und startet neu. Alles kostenlos:
Sparkle ist Open Source, Downloads liegen auf GitHub Releases, der Feed auf GitHub Pages.

Die Daten (Module, Notizen, Folien …) liegen im App-Container und bleiben bei Updates erhalten.

## Einmalige Einrichtung

1. **Sparkle einbinden:** In Xcode *File → Add Package Dependencies …*, URL
   `https://github.com/sparkle-project/Sparkle`, Version „Up to Next Major“ ab 2.6.0, Produkt **Sparkle**
   zum Target **StudyApp** hinzufügen. Der Code (`App/AppUpdater.swift`) erkennt das Paket automatisch.
2. **Schlüssel erzeugen:** `scripts/release.sh --setup` lädt die Sparkle-Werkzeuge und erzeugt das
   Schlüsselpaar. Der private Schlüssel landet im Schlüsselbund, ausgegeben wird der öffentliche.
   **Den privaten Schlüssel nie weitergeben;** ohne ihn lassen sich keine Updates mehr signieren
   (Sicherung: `build/sparkle/bin/generate_keys -x private-key.txt`).
3. **Öffentlichen Schlüssel eintragen:** in `Config/Info.plist` bei `SUPublicEDKey`.
4. **GitHub Pages aktivieren:** Repository → *Settings → Pages* → Branch `main`, Ordner `/docs`.
   Das Repository muss dafür öffentlich sein (kostenlos).
5. Optional die GitHub-CLI installieren und anmelden (`brew install gh`, `gh auth login`), dann lädt das
   Skript die DMG selbst hoch.

## Ein Release veröffentlichen

1. Release-Notizen schreiben: `docs/release-notes/<Version>.md`, eine Zeile pro Punkt („- …“).
2. `scripts/release.sh 1.2`
   - baut das Archiv mit Version 1.2 und einer neuen Build-Nummer (Zeitstempel),
   - erzeugt `build/release/updates/StudyApp-1.2.dmg`,
   - signiert die DMG und schreibt `docs/appcast.xml`,
   - lädt die DMG in das GitHub-Release `updates` hoch (falls `gh` angemeldet ist).
3. `docs/appcast.xml` committen und pushen. Ab dann bekommen alle Nutzer das Update angeboten.

Wichtig: `build/release/updates/` nicht löschen – `generate_appcast` baut den Feed aus allen DMGs darin
und erzeugt für ältere Versionen automatisch kleine Delta-Updates.

## Ohne bezahlten Developer Account

- Die erste Installation einer DMG aus dem Internet blockiert macOS: einmal **Rechtsklick → Öffnen**
  bzw. *Systemeinstellungen → Datenschutz & Sicherheit → Trotzdem öffnen*.
- Updates über Sparkle sind mit der Sparkle-Signatur (EdDSA) abgesichert. Die App wird mit dem
  Entwicklungszertifikat deines (kostenlosen) Apple-Teams signiert; bleibt das Team gleich, behält die
  App ihren Zugriff auf die gespeicherten Daten.
- Teste jedes Update zuerst auf deinem eigenen Mac (ältere Version installieren, dann „Nach Updates
  suchen …“).
