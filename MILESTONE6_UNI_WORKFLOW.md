# Milestone 6 — Uni-Workflow & neues Design

## Ziel
Der Stundenplan steuert die App: Module entstehen automatisch, die laufende Vorlesung öffnet sich von selbst, Notizen sind ohne Folien erreichbar.

## Features
- **Heute** (neue Startseite, ⌘0): laufende bzw. nächste Vorlesung mit Fortschritt, Tagesplan, fällige Karteikarten aller Module, zuletzt bearbeitete Notizen, Modulkacheln.
- **Module aus dem Kalender:** Termintitel werden analysiert (`CourseTitleAnalyzer`), Vorlesung/Übung/Tutorium desselben Fachs zusammengefasst und als Modul angelegt; alle Termine werden verknüpft. Läuft nach Import, Abo-Aktualisierung und App-Start. Gelöschte Module werden gemerkt und nicht neu angelegt. Prüfansicht: „Module aus Kalender erkennen …“.
- **Serienverknüpfung:** Im Termin-Dialog gilt die Modulzuordnung auf Wunsch für alle Termine der Veranstaltung.
- **Vorlesungs-Autopilot:** Beim Start (bzw. einmal beim Zurückkehren) während einer Vorlesung öffnet sich das Modul mit dem zuletzt gelesenen Foliensatz an der letzten Seite. Live-Karte in der Seitenleiste, ⇧⌘L.
- **Notizen ohne Folien:** Bereich „Notizen“ ist jetzt ein Editor (Markdown/LaTeX, Autosave). Freie Vorlesungsnotizen pro Termin, „In Folien öffnen“ springt auf die Seite. ⌘K durchsucht Notizinhalte.
- **Weiterlesen:** letzte Seite pro Foliensatz und zuletzt gelesener Foliensatz pro Modul werden gemerkt.
- **RRULE-Expansion** inkl. `EXDATE`, `RECURRENCE-ID`, `DURATION`, Windows-Zeitzonen.
- **Einstellungen (⌘,):** Erscheinungsbild, Automatik für Module/Abos/Autopilot, Vorlaufzeit.
- **Design:** helles, ruhiges Farbschema (Indigo-Akzent, weiße Karten mit weichen Schatten), neue Komponenten (`Components.swift`), Modul-Badges mit Initialen, Tab-Leiste statt Segmented Control; Dunkelmodus bleibt unterstützt.

## Behobene Fehler
- Nummerierte Markdown-Listen zeigten `\(ordinal).` statt `1.` (falsches Escaping).
- Export von Notizen schlug in der Sandbox fehl (`User Selected File` war nur lesend).
- Doppelte Fehler-Alerts in der Modulansicht (Folienfehler wurden zweimal präsentiert).
- Beim Löschen eines Moduls blieben Kalendertermine mit ungültiger Modul-ID zurück.
- Notizen wurden nach dem alten Dokumenttitel sortiert (falsche Reihenfolge nach Umbenennen).
- Wiederkehrende Vorlesungen erschienen nur einmal (RRULE wurde ignoriert).
- Parser: Doppelpunkt in gequoteten Parametern (`ALTREP="https://…"`) zerstörte den Wert; `DURATION` wurde ignoriert; pro Datum wurde ein neuer `DateFormatter` erzeugt.
- Veraltete `onChange`-API im Notizeditor; doppelte KaTeX-/README-/LICENSE-Kopien entfernt.

## Architektur
- `Domain/Entities/CourseTitle.swift`: Titelanalyse (Name, Kürzel, Art, Vergleichsschlüssel).
- `Domain/UseCases/ModuleDetectionUseCases.swift`: `DetectModuleCandidatesUseCase`, `ApplyModuleCandidatesUseCase`, `SyncModulesWithCalendarUseCase`, `LectureSchedule`.
- `Domain/UseCases/NoteUseCases.swift`: `CreateModuleNoteUseCase`, `UpdateNoteUseCase`. Freie Modulnotizen speichern die Modul-ID als `slideDocumentID` – kein Schema-Update nötig.
- `Presentation/Today/`, `Presentation/Settings/`, `Presentation/Navigation/LectureAutopilot.swift`, `Presentation/Notes/NoteEditingSession.swift`, `Presentation/Calendar/ModuleDetectionSheet.swift`.
- `AppNavigation.pendingIntent` (`ModuleIntent`) überbringt einmalige Aufträge an die Modulansicht (Folien fortsetzen, Notiz auswählen, Vorlesungsnotiz).

# Milestone 6.1 — PDF-Werkzeuge, Notizschrift, Architektur-Aufräumen

## Features
- **PDF-Werkzeuge:** Auswählen, Textmarker, Unterstreichen, Durchstreichen (7 Farben, Farbe pro Werkzeug gemerkt), Stift mit 3 Strichstärken, Textfelder auf der Folie, Radierer, Rückgängig. Markup-Werkzeuge markieren eine Auswahl sofort beim Loslassen der Maus.
- **Markierungsliste** in der Seitenleiste (Seiten | Markierungen) mit Sprung zur Stelle.
- **„In Notiz“ (⇧⌘E):** markierter Folientext wird als Zitat mit Foliennummer an die Notiz angehängt.
- **Notizschrift:** ⌘+ / ⌘− / ⌥⌘0, A−/A+ im Editor, Regler in den Einstellungen; Editor, Markdown, Tabellen, Formeln und Lernzettel skalieren mit.

## Architektur
- `FileStorage.write(_:as:)`: annotierte PDFs werden atomar über den Port gespeichert, nicht mehr per `FileManager` aus der Präsentationsschicht. Speichern ist entprellt und wird beim Schließen erzwungen.
- `StudySettingsStore` / `ReadingProgressStore` (Domain-Ports) mit `UserDefaultsStudyPreferences` (Data) und `InMemoryStudyPreferences` (Tests). ViewModels kennen kein `UserDefaults` mehr; reine Darstellungs-Einstellungen bleiben bei `@AppStorage` (`ViewPreferences`).
- Gemeinsame Helfer statt Duplikaten: `String.trimmed`/`isBlank` (5 Kopien entfernt), `LectureNote.previewLine()`/`hasContent`, `View.errorAlert` (7 Alert-Blöcke ersetzt).
- `ModuleDetailView` nutzt die Kalenderuhr (`referenceDate`) statt `Date()`; Fehler der Startseite werden angezeigt.
