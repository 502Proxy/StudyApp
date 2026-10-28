import AppIntents
import Foundation

/// What App Intents may do inside the running app. Registered with `AppDependencyManager` at launch,
/// so intents receive it through `@Dependency` instead of reaching for a global.
@MainActor
final class StudyAppIntentServices {
    private let modules: any ModuleRepository
    private let calendar: any StudyCalendarRepository
    private let flashcards: any FlashcardRepository
    private let navigation: AppNavigation
    private let now: () -> Date

    init(container: AppContainer, navigation: AppNavigation, now: @escaping () -> Date = { .now }) {
        modules = container.moduleRepository
        calendar = container.studyCalendarRepository
        flashcards = container.flashcardRepository
        self.navigation = navigation
        self.now = now
    }

    func activeModules() throws -> [StudyModule] {
        try modules.all().filter { !$0.isArchived }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func nextLectureText() throws -> String {
        let reference = now()
        return NextLectureUseCase.text(try NextLectureUseCase(calendar: calendar, modules: modules)(now: reference), now: reference)
    }

    func dueCardsText() throws -> String {
        DueCardsUseCase.text(try DueCardsUseCase(modules: modules, flashcards: flashcards)(now: now()))
    }

    func openFlashcards(moduleID: UUID) {
        navigation.show(module: moduleID, section: .flashcards)
    }
}
