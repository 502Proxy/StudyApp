# Features

The interface is in German; this document uses the German labels in quotes where it helps to find them in the app. Each section names the code that implements the feature.

## Today

A start page in two columns, titled with the date and a one-line summary. Left: the lecture running right now (progress and room) or the next one, today's timeline and recently edited notes. Right: assignments due within a week, due flashcards with „Lernen starten“ and upcoming exams. Narrow windows show one column. One click opens the slides of the current lecture or creates a lecture note for it.

Code: `Presentation/Today/`

## Timetable → modules

- Import a `.ics` file or subscribe to a calendar link (Stud.IP, HISinOne, Moodle …). Subscriptions refresh on launch, when the app becomes active and hourly while it is open.
- Recurring events are expanded completely, including exceptions and moved occurrences.
- Course titles such as „Analysis I (Vorlesung)“, „Übung zu Analysis I“ or „inf030 Programmierung, Tutorium“ are recognised; lecture, exercise and tutorial of the same subject become **one module**, and every occurrence is linked to it.
- Deleted modules are remembered and not recreated. „Module aus Kalender erkennen …“ shows all detected courses for review.

Code: `Domain/UseCases/ModuleDetectionUseCases.swift`, `Domain/Entities/CourseTitle.swift`, `Data/Calendar/`, `Presentation/Calendar/` · Details: [CALENDAR.md](CALENDAR.md)

## Lecture autopilot

Opening StudyApp during a lecture (or up to a configurable number of minutes before) jumps into that module and reopens the slides you read last, at the same page. It does so once per lecture, so you can navigate freely afterwards. ⇧⌘L opens the running lecture at any time.

Code: `Presentation/Navigation/LectureAutopilot.swift`, `LectureSchedule` in `Domain/UseCases/ModuleDetectionUseCases.swift`

## Slides

- Import PDFs into a module; StudyApp works on its own copy.
- Annotate: highlighter, underline, strikethrough, pen (three widths), text boxes, eraser, undo. Annotations are listed in the sidebar.
- Search the PDF with ⌘F; copy selected text into the current note as a quote with its page (⇧⌘E).

Code: `Presentation/Slides/`, `Domain/UseCases/SlideUseCases.swift`, `Data/PDF/`, `Data/Files/`

## Notes

- A note for the whole document and one per page, plus free lecture notes without any PDF.
- Plain text, Markdown or LaTeX with live preview (KaTeX, bundled offline). Supported math delimiters: `$…$`, `$$…$$`, `\(…\)`, `\[…\]`.
- Autosave, adjustable font size (⌘+ / ⌘−), export as Markdown, text or PDF.
- The „Notizen“ section lists every note of a module; ⌘K searches modules, sections and note content.

Code: `Presentation/Notes/`, `Presentation/Learning/NotesOverviewView.swift`, `Domain/UseCases/NoteUseCases.swift`, `Presentation/Export/`

## Flashcards and study sheets

- Question/answer cards, optionally created from a note. Review due cards and rate them „Nochmal“, „Schwer“, „Gut“ or „Leicht“ (keyboard: ↩ reveals, 1–4 rates). Scheduling is SM-2 inspired.
- Study sheets combine selected notes under a topic outline with generic self-check questions. They are assembled deterministically; nothing is AI-generated.
- Anki exchange (Karteikarten → „Anki“):
  - **Import** of `.apkg` packages and Anki text exports (`.txt`, `.tsv`, `.csv`) into the module. Imported cards are new and due now; cards whose front already exists in the module are skipped. Packages exported by Anki 2.1.50+ without „Unterstützung älterer Anki-Versionen“ only contain a compressed collection StudyApp cannot read; the message explains how to export them.
  - **Export** writes Anki's „Notizen als Klartext“ format (tab-separated, plain text, tags column with the module name), which Anki imports via „Datei → Importieren“.

Code: `Presentation/Learning/`, `Domain/UseCases/FlashcardUseCases.swift`, `Domain/UseCases/FlashcardExchangeUseCases.swift`, `Domain/UseCases/StudySheetUseCases.swift`, `Data/Anki/`

## Assignments

Assignments and submissions per module with due dates, shown on „Heute“, in the calendar, in the module and in „Aufgaben“ in the sidebar, which lists the assignments of all modules. The sidebar badge counts open assignments due within a week.

Code: `Presentation/Assignments/`, `Domain/UseCases/AssignmentUseCases.swift`

## Grades, ECTS and semester archive

- Credits and grade per module; credit-weighted average (failed modules do not count), earned and planned ECTS.
- Every module belongs to a semester („WiSe 2025/26“). The grade overview is grouped by semester with its own average.
- Finished semesters can be archived: they collapse into the „Archiv“ section of the sidebar and disappear from „Heute“, but still count towards the overall average.

Code: `Presentation/Grades/`, `Domain/UseCases/GradeUseCases.swift`, `Domain/Entities/Semester.swift`, `SemesterOverview` in `Domain/UseCases/ModuleUseCases.swift`

## Stud.IP

- Sign in with the university account in an embedded browser (two-factor authentication supported) or with a password.
- Link modules to Stud.IP courses; StudyApp suggests matches by title, course number and semester.
- New PDFs arrive in the module's slides; all other files appear under „Material → Dateien“ with their folder structure and are downloaded automatically up to 50 MB.

Code: `Presentation/StudIP/`, `Domain/UseCases/StudIPUseCases.swift`, `Data/StudIP/` · Details: [STUDIP.md](STUDIP.md)

## Menu bar

The menu bar item shows the remaining minutes while a lecture runs. Its window lists the running or next lecture (with „Folien öffnen“) and the due flashcards, and opens the main window. It can be hidden in Settings → Allgemein.

Code: `Presentation/MenuBar/`

## Updates and settings

- Automatic updates through Sparkle („Nach Updates suchen …“ in the app menu). See [RELEASING.md](RELEASING.md).
- Settings (⌘,): one toolbar tab per topic – Allgemein (appearance, note font size, lecture autopilot), Stundenplan, Stud.IP, Mitteilungen, Backup and Updates. The window remembers the last tab; each tab has a fixed height and scrolls, so the window fits on a laptop display.

Code: `App/AppUpdater.swift`, `Presentation/Settings/`

## Navigation

The sidebar shows the running lecture as a compact row, then Heute, Kalender, Aufgaben, Klausuren (all upcoming exams with their study plans, badge with the next countdown) and Noten & ECTS, the active modules and the archive. The Stud.IP status sits at the bottom; a click syncs.

⌘K opens the quick navigator, ⌘[ / ⌘] walk back and forward through history, ⌘1–⌘4 switch between the tabs of a module.

A module has four tabs: **Übersicht** (overview and exam plan), **Material** (slides and Stud.IP files), **Lernen** (notes, flashcards and study sheets) and **Aufgaben**. Tabs with several sections show a segmented control and remember the last section.

Code: `Presentation/Navigation/`
