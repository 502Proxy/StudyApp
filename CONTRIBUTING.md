# Contributing

## Workflow

1. Open or pick an issue; reference it in branch, commits and pull request.
2. Branch from `main`: `feat/<topic>`, `fix/<topic>`, `docs/<topic>`, `chore/<topic>`.
3. Keep a pull request focused on one change. Separate refactorings from behaviour changes.
4. Run `scripts/qa.sh` before pushing; CI must be green before merging.
5. Fill in the pull request template and close issues with `Fixes #<n>` / `Closes #<n>`.
6. User-visible changes get a line in `docs/release-notes/<next version>.md`.

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
