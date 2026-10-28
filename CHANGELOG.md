# Changelog

User-facing changes per version. The release notes shown in the update dialog live in `docs/release-notes/<version>.md` (German).

## Unreleased

- Settings in toolbar tabs; the window fits on a laptop display (#26)
- Neutral grey dark mode, blue accent and system colours for modules (#31)
- The app follows the system appearance by default (#31)
- Sidebar: compact row for the running lecture, new overviews „Aufgaben“ and „Klausuren“, Stud.IP status, single-line modules (#32)
- Today in two columns with a one-line summary; the module grid is gone (#33)
- Modules have four tabs – Übersicht, Material, Lernen, Aufgaben – with ⌘1–⌘4; the next exam shows in the header (#34)
- Expired Stud.IP sessions are checked on launch; a banner offers to sign in again (#40)
- Stud.IP announcements on Today and in the module, with optional notifications (#41)
- Timetable from Stud.IP: dates of linked courses in the calendar, cancelled dates marked (#42)
- Canteen menu of Mensa Uhlhornsweg and Mensa Wechloy on Today, loaded from the Studierendenwerk Oldenburg (#43, #67)
- Anki import (.apkg and text) and text export for flashcards (#44)
- Study timer (Pomodoro) in the toolbar with statistics per day, week and module (#45)
- Menu bar item with the running lecture, due cards and the study timer; built with AppKit after the SwiftUI scene hung the app at launch (#46, #64, #69)
- Shortcuts and Siri: next lecture, due cards, open a module's flashcards, start the study timer (#47, #70)
- Modules, notes and study sheets in Spotlight (#48)
- Widgets: next lecture, due cards and exam countdown (#49)
- Unit tests start an empty host app, so launch work never runs under XCTest (#62)

## 1.11 – 2026-10-28

- Exam phase: upcoming exams with countdown on Today, in the module (⌘8) and in the module overview (#16)
- Exams are detected from the calendar and can be entered by hand; a study plan spreads the slides over the days until the exam (#16)
- Notifications for lectures, assignment deadlines and new Stud.IP files; a click opens the matching place (#15)
- Backup and restore of all data including PDFs, plus weekly automatic backups (#17)
- App icon is shown again: the asset catalog is compiled into the bundle (#18)
- Repository documentation rewritten and moved to `docs/` (#19)

## 1.10 – 2026-10-22

- Recurring events show up completely again; previously only one occurrence per series was kept
- Quality checks: `scripts/qa.sh`, Git hooks and CI for lint, tests, release prerequisites and commit messages

## 1.9 – 2026-10-21

- Stud.IP sign-in through an embedded browser, including two-factor authentication
- Expired Stud.IP sessions are detected; background sync pauses until you sign in again
- Password sign-in remains available for accounts without 2FA

## 1.8 – 2026-10-21

- New „Dateien“ section per module with every file of the linked Stud.IP course, grouped by folder
- Files up to 50 MB are downloaded automatically; PDFs open in the slides
- The section bar of a module falls back to icons when space is tight

## 1.7 – 2026-10-21

- Stud.IP: link modules to courses and load new slides automatically
- Semester archive: finished semesters collapse, grades still count towards the average
- Grade overview grouped by semester with a per-semester average
- Calendar subscriptions refresh hourly, also while the app stays open

## 1.6 – 2026-10-21

- Test release for the automatic update flow

## 1.5 – 2026-10-21

- Fix: 1.4 crashed on launch because Sparkle.framework could not be loaded (library validation)

## 1.4 – 2026-10-21

- Sparkle integrated into the app build (crashes on launch, fixed in 1.5)

## 1.1 – 1.3

- Assignments and submissions with due dates on „Heute“ and in the calendar
- Grades and ECTS with a credit-weighted average
- Export notes and study sheets as PDF or print them
- Full-text search in PDFs (⌘F)
- Automatic updates via Sparkle
