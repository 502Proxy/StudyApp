# Quality assurance

The same checks run locally and in CI through `scripts/qa.sh`.

## Local commands

| Command | What it does |
| --- | --- |
| `scripts/qa.sh` | SwiftLint (strict) and unit tests – run before pushing |
| `scripts/qa.sh lint [--fix]` | SwiftLint with `.swiftlint.yml`; every warning fails |
| `scripts/qa.sh test` | `xcodebuild test` without signing; prints every failing expectation and writes `build/qa/Tests.xcresult` |
| `scripts/qa.sh build` | Unsigned Release build; fails if the app icon or the compiled asset catalog is missing from the bundle |
| `scripts/qa.sh release-check` | Sparkle key, feed URL, entitlement, valid appcast, versioned `Package.resolved`, release notes |
| `scripts/qa.sh commit-msg "<message>"` | Conventional Commit check (same rules as commitlint) |
| `scripts/qa.sh hooks` | Enables the Git hooks in `.githooks/` |

One-time setup: `brew install swiftlint xcbeautify`, then `scripts/qa.sh hooks`.

## Git hooks

| Hook | Check |
| --- | --- |
| `commit-msg` | Conventional Commit header, at most 100 characters |
| `pre-commit` | SwiftLint on the staged Swift files |
| `pre-push` | SwiftLint on the whole project |

## Continuous integration

| Workflow | Job | Runner |
| --- | --- | --- |
| `ci.yml` | SwiftLint | Ubuntu (SwiftLint Docker image) |
| `ci.yml` | Release-Voraussetzungen | Ubuntu |
| `ci.yml` | Build & Tests (macOS) – unit tests and Release build, `.xcresult` uploaded on failure | `macos-26`, latest stable Xcode |
| `commitlint.yml` | commitlint over all commits of the pull request | Ubuntu |

Dependabot updates the GitHub Actions monthly. To block red pull requests, add **SwiftLint**, **Build & Tests (macOS)** and **commitlint** as required status checks in the ruleset for `main`.

## SwiftLint configuration

`.swiftlint.yml` lints `App`, `Data`, `Domain`, `Presentation` and `StudyAppTests` (not the bundled KaTeX). Thresholds were tuned to the existing code; `trailing_comma` and `identifier_name` are disabled on purpose. Raise a threshold only with a reason in the file, and prefer refactoring over `swiftlint:disable`.
