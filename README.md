# StudyApp

StudyApp is a native macOS study workspace for university students. It connects your timetable with your lecture material: modules are created automatically from your calendar, the slides of the lecture that is running right now open by themselves, and notes, flashcards and study sheets live next to them. It combines a PDF reader with document-wide and page-specific notes, free lecture notes, Markdown and LaTeX previews, spaced-repetition flashcards, and editable study sheets.

The application is built with SwiftUI and SwiftData, uses PDFKit to display and annotate PDFs, and bundles KaTeX for local LaTeX rendering. The current implementation is local-first: it does not require an account, backend, or external AI service.

> **Project status:** The repository contains `StudyApp.xcodeproj`. It uses file-system synchronized groups, so new Swift files in `App/`, `Data/`, `Domain/`, `Presentation/` and `StudyAppTests/` are picked up by Xcode automatically. Open the project and run the `StudyApp` scheme.

## GitHub repository description

> A native macOS study workspace for organizing PDF lecture slides, taking page-specific Markdown/LaTeX notes, reviewing spaced-repetition flashcards, and compiling notes into structured study sheets. Built with SwiftUI, SwiftData, PDFKit, and bundled KaTeX.

## Contents

- [Features](#features)
- [Technology stack](#technology-stack)
- [Requirements](#requirements)
- [Installation and setup](#installation-and-setup)
- [Running the app](#running-the-app)
- [Running tests](#running-tests)
- [Quality assurance](#quality-assurance)
- [Architecture](#architecture)
- [Project structure](#project-structure)
- [Data storage and privacy](#data-storage-and-privacy)
- [Code conventions](#code-conventions)
- [Testing conventions](#testing-conventions)
- [Git workflow and commit messages](#git-workflow-and-commit-messages)
- [Troubleshooting](#troubleshooting)
- [Known limitations](#known-limitations)
- [Contributing](#contributing)
- [License](#license)

## Features

### Today dashboard

- A start page that shows the lecture running right now (with progress and room) or the next one, today's timeline, flashcards due across all modules, recently edited notes and all modules.
- One click opens the slides of the current lecture or creates a lecture note for it.

### Timetable → modules (automatic)

- Import a `.ics` file or subscribe to the calendar link of your university (Stud.IP, HISinOne, Moodle …).
- Recurring events (`RRULE`, `EXDATE`, moved occurrences via `RECURRENCE-ID`) are expanded completely.
- StudyApp recognizes courses in the event titles (e.g. „Analysis I (Vorlesung)“, „Übung zu Analysis I“, „inf030 Programmierung, Tutorium“), groups lecture, exercise and tutorial of the same subject, **creates one module per course** and links every occurrence.
- Events whose title matches an existing module (name or code) are linked automatically; linking one event in the calendar can apply to the whole series.
- Deleted modules are remembered and not recreated. „Module aus Kalender erkennen …“ shows all detected courses for review.

### Lecture autopilot

- When you open StudyApp during a lecture (or up to 10 minutes before), it jumps straight into that module and opens the slides you read last, at the page where you stopped.
- When returning to the app during the same lecture it only does that once, so you can switch freely.
- The running lecture is highlighted in the sidebar and on the module page (⇧⌘L opens it at any time).

### PDF lecture library

- Import one or more PDF files into a module.
- Open PDFs in an in-app reader and navigate their pages.
- Annotate the app-managed copy of an imported PDF: highlighter, underline and strikethrough in several colors, a pen for freehand drawing (three widths), text boxes on the slide, an eraser and undo.
- Browse all annotations of a document in the sidebar and jump to them.
- Copy selected slide text into the current note as a quote with its page (⇧⌘E).
- Rename or remove imported slide documents.
- Organize documents and learning material by module.

Imported PDFs are copied into the app's managed storage. Work with the copy inside StudyApp; do not assume the original file elsewhere on disk is modified.

### Notes alongside lecture slides

- Keep a document-wide note as well as a separate note for each PDF page.
- Write plain text, Markdown, or LaTeX.
- Preview Markdown separately from LaTeX, with KaTeX rendering for supported formulas.
- Use Markdown headings, paragraphs, lists, block quotes, code blocks, tables, and horizontal rules.
- Search notes associated with an open slide document and navigate to a result's page.
- Export the current note in a suitable text format, or export all notes for a document as Markdown.
- Save notes automatically while editing and when switching pages or closing the reader.
- Adjust the note font size (⌘+ / ⌘−, the A−/A+ control or Settings); editor, Markdown and LaTeX preview scale together.

Supported math delimiters include `$...$`, `$$...$$`, `\(...\)`, and `\[...\]`, depending on the preview context.

### Notes without opening the slides

- The **Notizen** section of a module lists all notes – free lecture notes and notes attached to slides – and lets you read and edit them directly (Markdown/LaTeX preview, autosave).
- Create free notes per lecture (e.g. „Vorlesung vom 19.10.2026“) without any PDF.
- „In Folien öffnen“ jumps from a slide note to its page in the reader.
- ⌘K searches modules, sections **and the content of all notes**.

### Flashcards and spaced repetition

- Create and edit question-and-answer flashcards.
- Start a card from a source note and refine the question and answer before saving.
- Review cards due for repetition.
- Rate a recall as **Again**, **Hard**, **Good**, or **Easy** to schedule the next review (keyboard: ↩ reveals, 1–4 rates).
- Keep review history and scheduling data between launches.

The scheduler is inspired by SM-2-style spaced repetition; it is a lightweight built-in implementation, not a claim of full compatibility with Anki or the original SM-2 specification.

### Study sheets

- Select multiple notes from a module to create a study sheet.
- Preserve source note content and organize it under a topic outline.
- Add generic self-check questions to support active recall.
- Store study sheets for later review and editing.

Study sheets are assembled deterministically from existing notes. **They are not AI-generated summaries** and do not currently rewrite or verify the source material.

## Technology stack

| Area | Technology | Responsibility |
| --- | --- | --- |
| App UI | SwiftUI | Native macOS interface and navigation |
| State observation | Observation / SwiftUI state | Presentation state and UI updates |
| Persistence | SwiftData | Local storage of modules, PDF metadata, notes, flashcards, and study sheets |
| PDF rendering and annotations | PDFKit | Displaying and annotating imported PDF copies |
| LaTeX preview | WebKit + bundled KaTeX | Offline-capable rendering of mathematical expressions |
| File access | Foundation and UniformTypeIdentifiers | File management and PDF importing |
| Unit tests | Swift Testing | Domain, use-case, data, and presentation logic tests |

There are no external package dependencies or server endpoints required by the current source. KaTeX assets are included in the repository and retain their own license file.

## Requirements

- A Mac running **macOS 14 or later** (SwiftData is used by the app).
- Xcode with a macOS SDK compatible with the deployment target. Swift 6.2 was used for source-level checks; a complete macOS/Xcode build still needs to be verified.
- Git, if cloning the repository.
- The Xcode app and test targets configured as described below.

## Installation and setup

### 1. Get the source

Clone the repository after it has been published to GitHub:

```bash
git clone <YOUR-REPOSITORY-URL>
cd <YOUR-REPOSITORY-DIRECTORY>
```

Replace the placeholders with the repository URL and directory name.

### 2. Check for an Xcode project

Look for `StudyApp.xcodeproj` or `StudyApp.xcworkspace` at the repository root. **The source archive this README was written for does not currently include either file.** If your GitHub repository also contains only the current source tree, create an Xcode project as follows. If the project file is available in a later revision, skip to step 6.

### 3. Create a macOS app project in Xcode

1. Open Xcode and choose **File → New → Project**.
2. Select **macOS → App**.
3. Set the product name to `StudyApp`.
4. Choose **SwiftUI** for the interface and **Swift** for the language.
5. Set the minimum deployment target to **macOS 14.0** or later.
6. Enable a unit-test target if the Xcode project template offers the option.
7. Save the `.xcodeproj` in the repository root or another clearly documented location.
8. Set a unique bundle identifier, for example `com.example.StudyApp`. Replace it with your own identifier before distribution.

Xcode creates a starter app entry point and often a `ContentView.swift`. The source tree already contains `App/StudyAppApp.swift`, which declares `@main`. Keep **exactly one** app entry point: replace or remove the generated entry point and starter view if they are no longer needed.

### 4. Add application source files

Add the source directories from this repository to the Xcode project. Use **Create groups** when adding ordinary source directories, or use an Xcode file-system-synchronized group if that is how the project is managed. Do not add the same Swift file twice.

Add all application `.swift` files from these directories to the **StudyApp app target**:

- `App/`
- `Data/`
- `Domain/`
- `Presentation/`

Do not add `StudyAppTests/` to the app target. Add its Swift files to the **StudyAppTests test target** instead.

If Xcode asks whether to copy files, keep one canonical copy inside the repository. Make sure the folder layout remains intact because resources and source references expect the directory structure to be preserved.

### 5. Bundle the KaTeX resources correctly

The LaTeX preview looks for `latex-preview.html` inside a bundled `KaTeX` directory. The active resource path used by `LaTeXWebView` is:

```text
Presentation/Resources/KaTeX/
```

In Xcode:

1. Add this `KaTeX` directory to the app target.
2. Choose **Create folder references** when prompted. In the Project navigator it should appear as a blue folder, not just a yellow group.
3. Open **Build Phases → Copy Bundle Resources** and confirm the `KaTeX` folder is copied into the app bundle.
4. Preserve the contents, including `latex-preview.html`, `katex.min.js`, `katex.min.css`, `contrib/`, and `fonts/`.
5. Keep the included KaTeX `LICENSE` file with the assets.

The Xcode project already references this folder as a folder reference and excludes its files from the synchronized `Presentation` group, so it is copied exactly once.

### 6. Configure target membership and app capabilities

In Xcode, select the project and configure the targets:

- **App target:** all app source files and the KaTeX folder resource.
- **Test target:** the files in `StudyAppTests/`.
- **Signing:** select your Apple Development team for local builds, or use automatic signing if appropriate.
- **Bundle identifier:** use a unique value for your environment.
- **Deployment target:** macOS 14.0 or later.

With App Sandbox enabled the app needs **User Selected File: Read/Write** (configured in the project): reading imported PDFs and `.ics` files, and writing exported notes. **Outgoing Connections (Client)** is enabled for calendar subscriptions. StudyApp copies selected PDFs into its app-managed storage before working with them.

LaTeX preview uses `WKWebView` and local bundled resources; it does not intentionally call an external service. If local WebKit rendering fails in a sandboxed development build, inspect the App Sandbox and resource-bundling configuration before enabling any broader permissions.

### 7. Verify persistence configuration

`Data/SwiftData/Persistence.swift` registers these SwiftData models:

- `ModuleRecord`
- `SlideDocumentRecord`
- `NoteRecord`
- `FlashcardRecord`
- `StudySheetRecord`

If adding this code to an existing project, make sure you use the updated `Persistence.swift` and keep the existing models registered. Do not replace the persistence schema with only the newest model types, as this would omit existing modules, slide documents, and notes. Test any schema changes against a copy of important local data before shipping.

### 8. Build and run

1. Select the `StudyApp` scheme.
2. Select **My Mac** as the run destination.
3. Choose **Product → Build** (`⌘B`).
4. Resolve any project-specific signing or target-membership warnings.
5. Choose **Product → Run** (`⌘R`).

On first launch, the app initializes its SwiftData container. Create a module, import a PDF, add document-wide or page-specific notes, and then open the Notes, Flashcards, or Study Sheets sections.

## Running the app

A typical workflow is:

1. Create a module for a course or subject.
2. Import the lecture PDF into the module.
3. Read the slides and highlight relevant passages.
4. Add a general note for the document or a separate note for the current page.
5. Use the notes overview to search and select useful material.
6. Create flashcards for facts or concepts that should be recalled without looking at the answer.
7. Review the cards that are due and rate how well you remembered each answer.
8. Create a study sheet from selected notes for a structured overview before an exam.

## Running tests

The test suite uses Apple's **Swift Testing** framework (`import Testing`, `@Test`, and `#expect`). In Xcode:

1. Confirm the test files have membership in `StudyAppTests` and not the app target.
2. Confirm the test target's **Host Application** / test configuration points to the `StudyApp` app target as needed by your Xcode version.
3. Select the `StudyApp` scheme.
4. Run **Product → Test** (`⌘U`).

Tests cover domain use cases, note handling, Markdown parsing, flashcard scheduling, learning-sheet generation, and repository behavior. The source-only environment used to prepare this README allowed syntax and selected source-level checks, but not a full macOS app build. Run the entire suite locally on macOS before relying on release status.

## Quality assurance

`scripts/qa.sh` runs the same checks locally and in CI:

| Command | What it does |
| --- | --- |
| `scripts/qa.sh` | SwiftLint (strict) and unit tests – run before pushing |
| `scripts/qa.sh lint [--fix]` | SwiftLint with `.swiftlint.yml`; every warning fails |
| `scripts/qa.sh test` | `xcodebuild test` without signing, result in `build/qa/Tests.xcresult` |
| `scripts/qa.sh build` | Unsigned Release build |
| `scripts/qa.sh release-check` | Sparkle key, feed URL, entitlement, valid appcast, release notes |
| `scripts/qa.sh commit-msg "<message>"` | Conventional Commit check (same rules as commitlint) |
| `scripts/qa.sh hooks` | Enables the Git hooks in `.githooks/` |

One-time setup on a Mac: `brew install swiftlint xcbeautify` and `scripts/qa.sh hooks`. The hooks check every commit message, lint staged Swift files before a commit and lint the project before a push.

GitHub Actions (`.github/workflows/ci.yml`) runs SwiftLint, the release check, the unit tests and a Release build on every pull request and on `main`; `commitlint.yml` checks the commit messages of a pull request. Dependabot keeps the actions up to date. To block merging red pull requests, add the checks **SwiftLint**, **Build & Tests (macOS)** and **commitlint** as required status checks in the ruleset for `main`.

## Architecture

The code follows a pragmatic Clean Architecture / ports-and-adapters approach. Dependencies point inward: UI code invokes domain use cases, while persistence implementations satisfy domain repository protocols.

```text
Presentation (SwiftUI Views + ViewModels)
                  |
                  v
         Domain Use Cases
                  |
                  v
      Domain Entities / Protocols
                  ^
                  |
Data (SwiftData repositories, PDFKit, local file storage)
                  |
                  v
       Apple frameworks / file system

AppContainer = composition root that wires the dependencies together
```

### Domain

`Domain/Entities/` contains framework-independent models such as `StudyModule`, `SlideDocument`, `LectureNote`, `Flashcard`, and `StudySheet`.

`Domain/Repositories/` defines protocols (ports), such as `NoteRepository`, `FlashcardRepository`, `StudySheetRepository`, and `FileStorage`. The domain should not import SwiftUI, SwiftData, PDFKit, or WebKit.

`Domain/UseCases/` contains application operations and rules, including validation, module deletion, note saving, spaced-repetition scheduling, and study-sheet creation. Keep reusable business decisions here rather than embedding them directly in views.

### Data

`Data/SwiftData/` contains persistence record types and SwiftData container setup. `Data/Repositories/` implements the repository protocols. `Data/Files/` manages app-owned PDF copies, and `Data/PDF/` adapts PDFKit to the domain's PDF-inspection abstraction.

Data implementations may depend on domain protocols and platform frameworks. Domain entities should not depend on the data layer.

### Presentation

`Presentation/` contains SwiftUI screens, observable view models, formatting helpers, and preview adapters. Views should focus on layout and user interaction. View models coordinate presentation state and call use cases or injected repository abstractions instead of implementing business rules themselves.

### Composition root and dependency injection

`App/AppContainer.swift` is the composition root: it creates the SwiftData container, repositories, storage adapters, and view models. Prefer constructor injection through this container over creating concrete repositories inside views or global singletons.

### Data ownership and deletion

Modules own their slide documents, notes, flashcards, and study sheets. When changing deletion behavior, preserve the cascade-cleanup rules and add tests for associated data. A flashcard may optionally reference a source note, but it should remain usable when that source note is absent.

## Project structure

```text
StudyApp/
├── App/
│   ├── AppContainer.swift
│   └── StudyAppApp.swift
├── Data/
│   ├── Files/
│   ├── PDF/
│   ├── Repositories/
│   └── SwiftData/
├── Domain/
│   ├── Entities/
│   ├── Repositories/
│   └── UseCases/
├── Presentation/
│   ├── DesignSystem/
│   ├── Learning/
│   ├── Modules/
│   ├── Notes/
│   └── Slides/
├── StudyAppTests/
├── MILESTONE2.md
├── MILESTONE3.md
├── MILESTONE4_LEARNING.md
└── README.md
```

The Xcode project file should live at the repository root when one is added. Keep documentation alongside the code it describes and update the milestone notes when a significant feature or integration requirement changes.

## Data storage and privacy

- StudyApp is currently a local-first macOS application.
- There is no sign-in flow, remote backend, analytics service, or AI API in the current implementation.
- Modules, notes, flashcards, study sheets, and PDF metadata are stored with SwiftData.
- Imported PDFs are copied to the app's Application Support directory under `StudyApp/Slides`.
- The app's data is local to the current macOS user and is not automatically synchronized across devices.
- The bundled KaTeX assets are used for mathematical rendering; the intended preview path is local.

Removing a module also removes learning resources that belong to it. Before testing destructive operations with important data, back up the app's local data or use a separate development environment.

## Code conventions

These conventions are intended to keep the codebase understandable and maintainable. Apply them consistently to new code and when touching existing code.

### Naming

- Use `UpperCamelCase` for types and protocols: `FlashcardRepository`, `CreateStudySheetUseCase`.
- Use `lowerCamelCase` for properties, functions, enum cases, and local variables: `dueAt`, `saveNote`, `case easy`.
- Give types and functions descriptive names that express responsibility; avoid abbreviations except for established terms such as `PDF` and `ID`.
- Prefer domain language (for example, `StudySheet` and `LectureNote`) over UI-specific names in the domain layer.

### Formatting and organization

- Use four spaces for indentation; do not use tabs.
- Keep one primary type per file where practical. Small, closely related private view/helper types may share a file.
- Group code by responsibility and keep files in the corresponding architectural directory.
- Use `// MARK: -` to divide long Swift files into meaningful sections, not to label every few lines.
- Prefer short functions with one clear responsibility. Extract complex conditions and transformations into named helpers.
- Avoid unexplained constants; name domain-significant values and document non-obvious choices.

### Swift and API design

- Prefer `struct` for value types and immutable data where appropriate.
- Use protocols at architectural boundaries where they provide meaningful substitution or testability; avoid unnecessary abstraction for trivial implementation details.
- Prefer `let` over `var` unless mutation is required.
- Use Swift optionals to represent genuine absence and handle them deliberately. Avoid force unwraps and `try!` in production code.
- Use `throws` and typed domain errors for recoverable failures. Present user-facing errors through the existing view-model / alert path rather than silently discarding them.
- Keep platform frameworks out of Domain files.
- Mark values `Sendable` when their concurrency semantics justify it, and respect actor isolation. Do not add `@MainActor` or `nonisolated` just to silence a warning without understanding the ownership model.
- Use dependency injection to make time, persistence, and other dependencies testable. In algorithms that depend on the current date, prefer an injected date or clock parameter in tests.
- Do not put business rules, database queries, or complex parsing logic directly into `body` properties.

### SwiftUI conventions

- Keep views declarative and focused on presentation.
- Move non-trivial state transitions and orchestration into the corresponding view model or use case.
- Use small subviews for repeated or conceptually independent UI components.
- Keep styling consistent with `Presentation/DesignSystem/Theme.swift` rather than scattering unrelated colors and spacing values throughout the app.
- Avoid putting persistence setup inside a view. Create dependencies in `AppContainer` and inject them.
- Provide useful empty states, loading/error feedback, and destructive-action confirmation where appropriate.

### Domain and data conventions

- Domain entities should express application concepts and invariants, not UI concerns or SwiftData annotations.
- Repository protocols belong in `Domain/Repositories/`; their SwiftData implementations belong in `Data/Repositories/`.
- Keep use cases focused on one application action. Validate user input in use cases when that validation is part of the business rule.
- Do not expose `ModelContext`, `@Model` records, or SwiftData types to the presentation or domain layers when a domain entity/protocol is sufficient.
- Update `Persistence.schema` when adding a SwiftData record, and consider migration implications before changing persisted fields or model identity.
- When adding a new model to a module, handle module deletion and add tests for the cleanup behavior.

### Markdown and LaTeX content

- Keep Markdown parsing and rendering logic separate from the editor's UI.
- Preserve KaTeX's license and bundled resources when updating the renderer.
- Treat note content as user data. Avoid evaluating arbitrary scripts or loading remote resources from note content.
- Add parser tests for new syntax, especially for block boundaries, escaping, tables, and math delimiters.

## Testing conventions

- Use `import Testing`, `@Test`, and `#expect` for the current test suite.
- Use test names that describe behavior, such as `failedRecallSchedulesQuickRetryAndResetsProgress`.
- Prefer tests of observable behavior over tests coupled to private implementation details.
- Use in-memory persistence and fake repositories for isolated domain/use-case tests.
- Inject fixed dates into scheduling or timestamp-sensitive behavior so tests are deterministic.
- Cover success paths, validation failures, missing records, and relevant cleanup/edge cases.
- For parser changes, add tests with representative Markdown inputs and expected output.
- For SwiftData schema or repository changes, run tests on macOS in Xcode; Linux source checks do not substitute for platform persistence tests.

## Git workflow and commit messages

A lightweight Conventional Commits format is recommended:

```text
feat(notes): support page-specific note search
fix(learning): preserve review schedule after editing a card
test(markdown): cover nested list rendering
docs(readme): document Xcode setup
refactor(domain): extract review interval calculation
```

Suggested workflow:

1. Create a focused branch for one feature or fix.
2. Keep changes small and avoid mixing refactors with unrelated behavior changes.
3. Add or update tests alongside code changes.
4. Build and run the test suite in Xcode.
5. Review resource membership, target membership, and data migrations before opening a pull request.
6. Update this README when requirements, setup steps, user-facing behavior, or limitations change.

## Troubleshooting

### The project cannot be opened from the downloaded source

The current source archive does not contain `.xcodeproj` or `.xcworkspace`. Create an Xcode macOS App project and add the source files as described in [Installation and setup](#installation-and-setup), or obtain a repository revision that includes the project file.

### LaTeX appears as source text or the preview says KaTeX is missing

Confirm that `Presentation/Notes/Resources/KaTeX` is included in the app target as a blue folder reference and appears in **Copy Bundle Resources**. Check that `latex-preview.html`, JavaScript, CSS, and the `fonts/` directory are present in the built app bundle.

### PDFs cannot be imported or read

Check the target's sandbox file-access entitlement for user-selected files. Confirm the PDF is valid and not password protected. Make sure the app is operating on the copied PDF in its Application Support directory.

### Existing data appears to be missing after an Xcode change

Confirm that the original model types remain registered in `Persistence.schema`, the app uses the expected bundle identifier/container, and the development build has not switched to a different app sandbox. Avoid deleting app data while diagnosing persistence problems.

### A new Swift file does not compile as part of the app or tests

Check **Target Membership** in the File inspector. Production files belong to the app target; test files belong to `StudyAppTests`. Also check for duplicate source-file references and more than one `@main` app declaration.

## Known limitations

- Course detection is heuristic (title keywords, weekly pattern). Unusual titles may need a manual link or the review sheet „Module aus Kalender erkennen …“.
- Recurring events without an end are expanded for about one year ahead; `BYSETPOS` and hourly/minutely rules are not supported.
- Study sheets organize source notes and add generic self-check questions; they do not use an AI model to summarize or fact-check material.
- There is no cloud synchronization or cross-device sync.
- Spaced repetition is an SM-2-inspired implementation and has not been validated as equivalent to another learning application's algorithm.
- The interface text is currently primarily German, even though this repository documentation is in English.

## Contributing

Contributions and focused bug reports are welcome. Before submitting a change, describe the problem being solved, keep the implementation within the existing architectural boundaries, add tests for behavior changes, and verify the app and tests in Xcode whenever possible. Please include reproduction steps and relevant macOS/Xcode versions in bug reports.

## License

No project-wide license is currently specified. Until a `LICENSE` file is added, do not assume that the application source is released under an open-source license. The bundled KaTeX distribution includes its own license file; preserve it and review all third-party notices before redistribution.

## Calendar

The Calendar screen supports importing `.ics` files and subscribing to an HTTP(S) iCalendar feed. Imported events are stored locally using SwiftData. Subscribed feeds are refreshed on launch (if older than three hours) and on demand. Events are linked to modules automatically (see *Timetable → modules*); a link can also be set manually for one event or the whole series.

The built-in parser handles common `VEVENT` properties (`UID`, `DTSTART`, `DTEND`, `DURATION`, `SUMMARY`, `DESCRIPTION`, `LOCATION`, `STATUS`), UTC/floating/`TZID` timestamps (including common Windows zone names), escaped text, quoted parameters and folded content lines. Recurring events (`RRULE` with `FREQ` DAILY/WEEKLY/MONTHLY/YEARLY, `INTERVAL`, `COUNT`, `UNTIL`, `BYDAY`, `BYMONTHDAY`, `BYMONTH`), `EXDATE` and `RECURRENCE-ID` overrides are expanded into individual events with stable IDs, so module links survive refreshes.

### Settings

**StudyApp → Einstellungen… (⌘,)**: appearance (light by default, dark or system), automatic module creation, refresh on launch, lecture autopilot and how many minutes before a lecture it already opens the slides.
