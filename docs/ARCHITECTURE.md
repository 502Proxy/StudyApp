# Architecture

StudyApp follows a pragmatic Clean Architecture (ports and adapters). The goal is simple: business rules can be read and tested without SwiftUI, SwiftData, PDFKit or the network.

## Layers and the dependency rule

```text
┌──────────────────────────────────────────────────────────────┐
│ App            AppLauncher (@main) · StudyAppApp · AppContainer │  wires everything together
├──────────────────────────────────────────────────────────────┤
│ Presentation   SwiftUI views · @Observable view models         │
├──────────────────────────────────────────────────────────────┤
│ Domain         Entities · use cases · repository protocols     │  no Apple UI/persistence frameworks
├──────────────────────────────────────────────────────────────┤
│ Data           SwiftData · files · PDFKit · iCalendar ·        │  implements the domain protocols
│                Stud.IP JSON:API · keychain                     │
└──────────────────────────────────────────────────────────────┘
```

Dependencies point **inward**: Presentation and Data both depend on Domain, Domain depends on nothing but Foundation. Data never imports Presentation, and Presentation never touches SwiftData records or `ModelContext`.

| Layer | Folder | May import | Contains |
| --- | --- | --- | --- |
| Domain | `Domain/` | Foundation | `Entities/` (value types such as `StudyModule`, `Semester`, `CourseFile`), `Repositories/` (protocols = ports), `UseCases/` (one application action each), `Support/` |
| Data | `Data/` | Domain, SwiftData, PDFKit, Security, URLSession | `SwiftData/` (`@Model` records + mapping), `Repositories/` (SwiftData implementations), `Calendar/`, `StudIP/`, `Files/`, `PDF/`, `Preferences/` |
| Presentation | `Presentation/` | Domain, SwiftUI, AppKit, WebKit | One folder per feature with views and view models; `DesignSystem/` for shared components and `Theme` |
| Shared | `Shared/` | Foundation | Data contract between app and widget extension (`WidgetSnapshot`, `StudyAppLink`) |
| Widgets | `Widgets/` | Shared, WidgetKit, SwiftUI | Widget extension; reads the snapshot only |
| App | `App/` | everything | `AppContainer` (composition root), `AppLauncher`, `StudyAppApp`, `AppUpdater` |

## Composition root

`App/AppContainer.swift` is the only place that knows concrete implementations. It creates the SwiftData container, every repository and adapter, and offers factory methods such as `makeModulesViewModel()` or `makeCourseFilesViewModel(module:)`. Views receive view models or factory closures (`SlidesViewModelFactory`, `CourseFilesViewModelFactory`) instead of creating dependencies themselves.

`AppContainer(inMemory: true)` swaps in in-memory persistence and preferences for previews and tests.

`AppLauncher` is the entry point: under XCTest it starts an empty host app instead of `StudyAppApp`, so launch work (database, sync, menu bar item) never runs during unit tests. On CI runners the menu bar scene kept the test host from finishing its launch.

## Data flow example: calendar subscription → module

1. `StudyCalendarViewModel.subscribe(to:)` normalises the address (`CalendarFeedURL`) and calls `SyncCalendarSubscriptionUseCase`.
2. The use case loads the feed through the `CalendarFeedLoader` port (`URLSessionCalendarFeedLoader`) and parses it through `CalendarEventParsing` (`ICalendarFeedParser`).
3. `StudyCalendarRepository.replaceEvents` stores the events, matching them by their external ID so module links survive refreshes.
4. `SyncModulesWithCalendarUseCase` runs `DetectModuleCandidatesUseCase` (pure function over events and modules) and `ApplyModuleCandidatesUseCase` creates modules and links the events.
5. The view model reloads; `onModulesChanged` tells the other view models to reload as well.

## Concurrency

- The app target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` with approachable concurrency: types are main-actor isolated unless marked otherwise.
- Repositories, use cases and view models run on the main actor. Network calls (`URLSession`) and file I/O suspend without blocking it.
- Code that SwiftData calls outside the main actor (for example `ModuleRecord.toDomain()`) may only use `nonisolated` members – see `Semester.init(rawValue:)`.
- Long-running background loops live in `StudyAppApp` (`keepClockRunning`, `keepSourcesFresh`) and are cancelled with the window's task.

## Persistence and migrations

- Every `@Model` type is registered in `Data/SwiftData/Persistence.swift`.
- SwiftData performs lightweight migration. New properties on existing records must therefore be **optional** (or have a default), e.g. `ModuleRecord.semesterRaw`, `SlideDocumentRecord.remoteID`.
- Records map to domain entities with `init(_ entity:)`, `toDomain()` and `apply(_:)`; domain code never sees a record.
- Files are referenced by name; the `FileStorage` port resolves them inside the app container.

## Design patterns in use

| Pattern | Where | Why |
| --- | --- | --- |
| Ports and adapters (repository) | `Domain/Repositories/*` ↔ `Data/Repositories/*`, `StudIPService` ↔ `StudIPJSONAPIClient` | Swap persistence and network for fakes in tests |
| Use case / command object | `Domain/UseCases/*` (`callAsFunction`) | One application action per type, easy to compose and test |
| Composition root + dependency injection | `AppContainer`, initialiser injection everywhere | No singletons, explicit dependencies |
| Factory | `make…ViewModel` methods and `…ViewModelFactory` closures | Views create per-module view models without knowing their dependencies |
| Adapter | `PDFKitInspector`, `KeychainStudIPAccountStore`, `UserDefaultsStudyPreferences`, `URLSessionCalendarFeedLoader` | Wrap Apple frameworks behind domain protocols |
| Observer | `@Observable` view models, `onModulesChanged` / `onSlidesChanged` callbacks | UI updates and cross-feature refreshes without tight coupling |
| Data mapper | SwiftData records ↔ domain entities | Keep persistence details out of the domain |
| Value objects | `Semester`, `CourseTitle`, `GradeSummary`, `StudIPAuthorization` | Encode rules (parsing, ordering, validation) next to the data |

Introduce a new pattern only when it removes real complexity; a plain function is often enough.

## Testing strategy

- Domain and view-model logic is tested with Swift Testing and in-memory fakes (`FakeModuleRepository`, `FakeStudIPService`, …) – fast and deterministic, with injected clocks (`now:`).
- SwiftData repositories are tested against an in-memory `ModelContainer`.
- The CI runs every test on macOS (`scripts/qa.sh test`); see [QUALITY.md](QUALITY.md).
