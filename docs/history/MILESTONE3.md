# StudyApp – Milestone 3: Vorlesungsnotizen

Notizen neben den Folien: Einfacher Text, Markdown und LaTeX, mit Live-Vorschau und Autosave.

## 1. Dateien einspielen

**Ersetzen** (gleicher Pfad, alte Datei überschreiben):
- `App/AppContainer.swift`
- `Data/SwiftData/Persistence.swift`
- `Domain/UseCases/ModuleUseCases.swift`
- `Domain/UseCases/SlideUseCases.swift`
- `Presentation/Modules/ModuleDetailView.swift`
- `Presentation/Modules/ModulesViewModel.swift`
- `Presentation/Slides/SlideReaderView.swift`
- `Presentation/Slides/SlidesView.swift`
- `Presentation/Slides/SlidesViewModel.swift`
- `StudyAppTests/ModuleUseCaseTests.swift`
- `StudyAppTests/SlideUseCaseTests.swift`

**Neu** (in Xcode in die passende Gruppe ziehen, "Create groups"):
- `Domain/Entities/NoteFormat.swift`, `Domain/Entities/LectureNote.swift`
- `Domain/Repositories/NoteRepository.swift`
- `Domain/UseCases/NoteUseCases.swift`
- `Data/SwiftData/NoteRecord.swift`
- `Data/Repositories/SwiftDataNoteRepository.swift`
- `Presentation/Notes/` (6 Swift-Dateien: `NoteEditorView`, `NotesViewModel`, `NoteFormat+Display`,
  `MarkdownBlockParser`, `MarkdownPreviewView`, `LaTeXWebView`)
- `StudyAppTests/NoteUseCaseTests.swift`, `NoteDataTests.swift`, `NotesViewModelTests.swift`,
  `MarkdownBlockParserTests.swift` (Target Membership: nur `StudyAppTests`)

## 2. KaTeX einbinden (wichtig für LaTeX)

Der Ordner `Presentation/Notes/Resources/KaTeX` enthält KaTeX 0.16.45 (MIT-Lizenz, `LICENSE` liegt dabei)
samt `latex-preview.html`. Er muss **als Ordnerreferenz** ins Target `StudyApp`:

1. In Xcode den Ordner `KaTeX` ins Projekt ziehen.
2. Im Dialog **"Create folder references"** wählen (der Ordner wird blau), Target `StudyApp` anhaken.
3. Unter Build Phases → Copy Bundle Resources muss `KaTeX` als Ordner erscheinen.

Ohne Ordnerreferenz gehen die Unterordner `contrib` und `fonts` verloren. Die LaTeX-Vorschau zeigt dann
statt der Formeln den Quelltext und einen Hinweis.

## 3. Sandbox prüfen
Target `StudyApp` → Signing & Capabilities → App Sandbox → Network:
**Outgoing Connections (Client)** aktivieren. `WKWebView` startet in sandboxed Mac-Apps sonst
nicht zuverlässig, auch wenn nur lokale Dateien geladen werden. Es werden keine Netzwerkzugriffe gemacht.

## 4. Datenbank
Das SwiftData-Schema bekommt ein neues Modell (`NoteRecord`). Das ist eine automatische, einfache
Migration, bestehende Module und Folien bleiben erhalten.

## 5. Ausprobieren
- Folien öffnen → Stift-Symbol in der Werkzeugleiste oder ⌥⌘N blendet die Notizen rechts ein.
- Format oben wählen: **Einfacher Text**, **Markdown**, **LaTeX**. Bei Markdown und LaTeX schaltet
  "Text / Beides / Vorschau" zwischen Editor, geteilter Ansicht und reiner Vorschau um.
- LaTeX: `$a^2 + b^2 = c^2$` (inline) oder `$$\int_0^1 x\,dx$$` (abgesetzt). Auch `\( … \)`, `\[ … \]`.
- Gespeichert wird automatisch kurz nach der letzten Eingabe, beim Ausblenden, beim Schließen der
  Folien und wenn die App in den Hintergrund geht oder beendet wird.
- Folien oder Modul löschen entfernt auch die zugehörigen Notizen.

## Architektur in Kürze
- **Domain:** `LectureNote`, `NoteFormat`, `NoteRepository` (Protokoll), Use Cases `GetNote`, `SaveNote` (Upsert,
  `updatedAt` ändert sich nur bei echten Änderungen, Uhr injizierbar), `DeleteNote` (per ID oder pro Folien-Dokument).
  `DeleteSlideDocumentUseCase` und `DeleteModuleUseCase` löschen Notizen mit.
- **Data:** `NoteRecord` und `SwiftDataNoteRepository`. Unbekannte Format-Werte fallen auf Einfacher Text zurück.
- **Presentation:** `NotesViewModel` (Debounce-Autosave, ein ViewModel pro geöffnetem Dokument), `NoteEditorView`,
  `MarkdownBlockParser` (reine Logik, getestet) plus `MarkdownPreviewView`, `LaTeXWebView` als Adapter auf
  `WKWebView`. Verdrahtung per Factory (`NotesViewModelFactory`) im `AppContainer`, wie bei den Folien.

## Notizen: Umfang und Bedienung
- Es gibt eine Notiz für das Gesamtdokument und zusätzlich jeweils eine Notiz pro PDF-Seite. Beim Blättern wird die seitenspezifische Notiz automatisch gewechselt; offene Änderungen werden davor gespeichert.
- Markdown unterstützt Überschriften, Absätze, Listen, Zitate, Codeblöcke, Tabellen und horizontale Linien. Ein einzelner Zeilenumbruch folgt der Markdown-Semantik; eine Leerzeile beginnt einen neuen Absatz.
- Inline- und abgesetzte LaTeX-Formeln werden auch innerhalb von Markdown-Notizen mit den gebündelten KaTeX-Ressourcen gerendert. Die Markdown- und LaTeX-Vorschau bleiben eigenständige Modi.
- Die Suche durchsucht alle Notizen des geöffneten Foliensatzes. Treffer zeigen die zugehörige Seite und springen beim Öffnen dorthin.
- Export ist für die aktuelle Notiz (TXT, Markdown oder LaTeX, abhängig vom Format) sowie für alle Notizen eines Foliensatzes als Markdown verfügbar.
