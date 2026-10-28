import AppIntents
import Foundation

/// „Was habe ich als Nächstes?“
nonisolated struct NextLectureIntent: AppIntent {
    static let title: LocalizedStringResource = "Nächste Vorlesung"
    static let description = IntentDescription("Sagt, welche Vorlesung gerade läuft oder als Nächstes ansteht.")

    @Dependency private var services: StudyAppIntentServices

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let text = try services.nextLectureText()
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

/// „Wie viele Karten sind fällig?“
nonisolated struct DueCardsIntent: AppIntent {
    static let title: LocalizedStringResource = "Fällige Karteikarten"
    static let description = IntentDescription("Zählt die fälligen Karteikarten je Modul.")

    @Dependency private var services: StudyAppIntentServices

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let text = try services.dueCardsText()
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

/// „Starte Karteikarten Analysis“: opens the module's flashcards.
nonisolated struct OpenFlashcardsIntent: AppIntent {
    static let title: LocalizedStringResource = "Karteikarten lernen"
    static let description = IntentDescription("Öffnet die Karteikarten eines Moduls in StudyApp.")
    static let openAppWhenRun = true

    @Parameter(title: "Modul")
    var module: ModuleEntity

    @Dependency private var services: StudyAppIntentServices

    @MainActor
    func perform() async throws -> some IntentResult {
        services.openFlashcards(moduleID: module.id)
        return .result()
    }
}

/// Siri phrases and the actions shown in the Shortcuts app without any setup.
nonisolated struct StudyAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextLectureIntent(),
            phrases: [
                "Was habe ich als Nächstes in \(.applicationName)?",
                "Nächste Vorlesung in \(.applicationName)",
            ],
            shortTitle: "Nächste Vorlesung",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: DueCardsIntent(),
            phrases: [
                "Fällige Karten in \(.applicationName)",
                "Wie viele Karten sind in \(.applicationName) fällig?",
            ],
            shortTitle: "Fällige Karten",
            systemImageName: "rectangle.stack"
        )
        AppShortcut(
            intent: OpenFlashcardsIntent(),
            phrases: [
                "Starte Karteikarten \(\.$module) in \(.applicationName)",
                "Karteikarten in \(.applicationName) lernen",
            ],
            shortTitle: "Karteikarten lernen",
            systemImageName: "brain.head.profile"
        )
    }
}
