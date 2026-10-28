# Contributing

## Workflow

Every change starts as an issue – features, bugs, design work and housekeeping alike.

1. **Issue:** open it through a form (bug report or feature request). Give it a type label, an area label and the milestone of the release it should ship in.
2. **Branch** from `main`: `feat/<topic>`, `fix/<topic>`, `docs/<topic>`, `chore/<topic>`.
3. **Pull request:** focused on one change; separate refactorings from behaviour changes. The title is a Conventional Commit, the body starts with `Closes #<n>`, labels and milestone match the issue.
4. **Checks:** run `scripts/qa.sh` before pushing; CI must be green before merging.
5. **Release notes:** user-visible changes get a line in `docs/release-notes/<next version>.md` and `CHANGELOG.md`.
6. **Merge** with a merge commit; the issue closes automatically.

## Labels

| Kind | Labels |
| --- | --- |
| Type (exactly one) | `bug`, `enhancement`, `design`, `documentation`, `refactor`, `maintenance` |
| Area (one or more) | `area: calendar`, `area: modules`, `area: slides`, `area: notes`, `area: learning`, `area: studip`, `area: exams`, `area: notifications`, `area: backup`, `area: settings`, `area: updates` |
| Priority | `priority: high` – should go into the next release |
| Triage | `question`, `duplicate`, `invalid`, `wontfix`, `good first issue`, `help wanted` |

Dependabot adds `dependencies` and `github_actions` itself. GitHub's generated release notes are grouped by type label (`.github/release.yml`).

## Milestones

One milestone per release, named after the version (`1.12`). An issue gets the milestone of the release it is planned for; what does not fit is moved to the next one. A milestone is closed when its release is published, so the milestone page shows what each version contained.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org), enforced by the `commit-msg` hook and commitlint:

```text
feat(studip): download course files automatically
fix(calendar): give every occurrence of a recurring event its own ID
docs: describe the backup format
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`. Header at most 100 characters, imperative mood, English.

## Code conventions

### Language

- **Code, identifiers and code documentation are written in English.**
- User-facing text in the app is German.
- Older comments are still partly German; translate them when you touch the code.

### Architecture

Follow the dependency rule in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md):

- Business rules belong in `Domain/` (entities and use cases), not in views.
- New external systems get a protocol in `Domain/Repositories/` and an adapter in `Data/`.
- Wire new dependencies in `AppContainer`; use initialiser injection, no singletons.
- Inject time (`now: () -> Date`) and other non-deterministic inputs so they can be tested.

### Swift

- Prefer value types and `let`; keep functions short with one responsibility.
- No force unwraps or `try!` in production code; model recoverable failures as typed errors with a German `errorDescription`.
- Document every non-private type and every non-obvious function with `///` doc comments that explain *why*, not *what*.
- Respect actor isolation; use `nonisolated` only where a caller really runs off the main actor.
- New SwiftData properties must be optional (lightweight migration); register new models in `Persistence.schema`.

### SwiftUI

- Views describe layout; state changes and orchestration live in the view model.
- Reuse components and tokens from `Presentation/DesignSystem/` (`Theme`, `Pill`, `EmptyStateView`, …).
- Provide empty states, progress feedback and confirmation for destructive actions.

## Tests

- Swift Testing (`import Testing`, `@Test`, `#expect`); test names describe behaviour, e.g. `changedFileComesInAsAdditionalDocument`.
- Use the in-memory fakes in `StudyAppTests/` for domain and view-model tests and an in-memory `ModelContainer` for SwiftData repositories.
- Cover the success path, validation failures and cleanup (for example when a module is deleted).
- Inside `#expect`, use closures instead of key paths for `contains(where:)` / `allSatisfy` – the macro turns key-path arguments into throwing calls.
