# StudyApp

StudyApp is a native macOS study workspace for university students. It connects your timetable, your lecture material and your learning:

- **Timetable → modules:** subscribe to your university calendar; every course becomes a module and every occurrence is linked to it.
- **Lecture autopilot:** open the app during a lecture and the slides of that lecture are already open, at the page where you stopped.
- **Slides, notes and learning:** annotate PDFs, write Markdown/LaTeX notes per page or per lecture, review flashcards with spaced repetition and compile study sheets.
- **Stud.IP:** sign in (including two-factor authentication), link modules to courses and let new slides and files arrive automatically.
- **Organisation:** assignments with deadlines, grades and ECTS per semester, semester archive, automatic updates.

All data stays on your Mac. There is no account, no backend and no analytics.

## Quick start

Requirements: macOS 26.5 and Xcode 26 or later.

```bash
git clone https://github.com/502Proxy/StudyApp.git
cd StudyApp
open StudyApp.xcodeproj        # run the "StudyApp" scheme with ⌘R
```

Xcode resolves the only package dependency, [Sparkle](https://sparkle-project.org), on first build. For contributing, also install the quality tools once:

```bash
brew install swiftlint xcbeautify
scripts/qa.sh hooks            # commit-msg, pre-commit and pre-push hooks
scripts/qa.sh                  # SwiftLint (strict) + unit tests
```

## Documentation

| Document | Contents |
| --- | --- |
| [Features](docs/FEATURES.md) | What the app does and where each feature lives in the code |
| [Architecture](docs/ARCHITECTURE.md) | Layers, dependency rule, composition root, concurrency, design patterns |
| [Calendar](docs/CALENDAR.md) | iCalendar support, subscriptions, course detection |
| [Stud.IP](docs/STUDIP.md) | Sign-in (password or browser with 2FA), JSON:API endpoints, sync rules |
| [Quality assurance](docs/QUALITY.md) | `scripts/qa.sh`, Git hooks, CI, SwiftLint configuration |
| [Releasing](docs/RELEASING.md) | Building a DMG, signing updates, publishing the appcast |
| [Design](docs/DESIGN.md) | Colour tokens, dark mode rules and mockups |
| [Contributing](CONTRIBUTING.md) | Issue workflow, labels, milestones, commit messages, code and test conventions |
| [Security](SECURITY.md) | Reporting vulnerabilities |
| [Changelog](CHANGELOG.md) | User-facing changes per version |

## Project structure

```text
App/              Entry point, composition root (AppContainer), updater
Domain/           Entities, repository protocols (ports) and use cases – no UI or persistence frameworks
Data/             Adapters: SwiftData, files, PDFKit, iCalendar parser, Stud.IP client, keychain
Presentation/     SwiftUI views and observable view models, grouped by feature
StudyAppTests/    Swift Testing suites with in-memory fakes
Config/           Info.plist and entitlements
docs/             Documentation, release notes and the update feed (served via GitHub Pages)
scripts/          qa.sh (quality checks) and release.sh (DMG + update feed)
```

## Data and privacy

- Modules, notes, flashcards, study sheets, assignments, calendar events and the Stud.IP file catalog are stored with SwiftData in the app's sandbox container.
- Imported PDFs and downloaded Stud.IP files live in `~/Library/Containers/<bundle id>/Data/Library/Application Support/StudyApp/Slides`.
- Network access is limited to calendar subscriptions, Stud.IP and the update feed. The Stud.IP password or session is kept in the macOS keychain only.

## License

StudyApp is released under the [Apache License 2.0](LICENSE). The bundled KaTeX distribution (`Presentation/Resources/KaTeX`) keeps its own MIT license; Sparkle is licensed under the MIT license.
