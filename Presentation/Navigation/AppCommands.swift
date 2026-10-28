import SwiftUI

/// Menübefehle und Tastaturkürzel für die Navigation. Sie greifen direkt auf den App-weiten
/// Navigationszustand zu und funktionieren daher unabhängig davon, welche Ansicht den Fokus hat.
struct AppCommands: Commands {
    let navigation: AppNavigation
    let calendar: StudyCalendarViewModel
    let assignments: AssignmentsViewModel
    @AppStorage(ViewPreferences.noteFontSizeKey) private var noteFontSize = NoteFontSize.standard

    var body: some Commands {
        CommandMenu("Navigation") {
            Button("Gehe zu …") { navigation.isQuickNavigatorPresented = true }
                .keyboardShortcut("k", modifiers: .command)

            Button("Heute") { navigation.showToday() }
                .keyboardShortcut("0", modifiers: .command)

            Button("Kalender") { navigation.showCalendar() }
                .keyboardShortcut("c", modifiers: [.command, .shift])

            Button("Aufgaben") { navigation.showAssignments() }

            Button("Klausuren") { navigation.showExams() }

            Button("Noten & ECTS") { navigation.showGrades() }

            Button("Neue Aufgabe …") { assignments.startNewAssignment(moduleID: navigation.selectedModuleID) }
                .keyboardShortcut("t", modifiers: [.command, .option])

            Button("Laufende Vorlesung öffnen") {
                if let moduleID = calendar.currentLecture?.moduleID {
                    navigation.show(module: moduleID, section: .slides, intent: .resumeSlides)
                }
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(calendar.currentLecture?.moduleID == nil)

            Divider()

            ForEach(Array(ModuleSection.allCases.enumerated()), id: \.element) { index, section in
                Button(section.title) { navigation.show(section: section) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .disabled(navigation.selectedModuleID == nil)
            }

            Divider()

            Button("Zurück") { navigation.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!navigation.canGoBack)
            Button("Vorwärts") { navigation.goForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!navigation.canGoForward)
        }

        CommandGroup(after: .toolbar) {
            Button("Notizschrift vergrößern") { noteFontSize = NoteFontSize.larger(noteFontSize) }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(noteFontSize >= NoteFontSize.range.upperBound)
            Button("Notizschrift verkleinern") { noteFontSize = NoteFontSize.smaller(noteFontSize) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(noteFontSize <= NoteFontSize.range.lowerBound)
            Button("Notizschrift zurücksetzen") { noteFontSize = NoteFontSize.standard }
                .keyboardShortcut("0", modifiers: [.command, .option])
            Divider()
        }

        CommandMenu("Kalender") {
            Button("Zu heute springen") {
                navigation.showCalendar()
                calendar.goToToday()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Button("Vorheriger Monat") { calendar.showMonth(offset: -1) }
                .disabled(navigation.destination != .calendar)
            Button("Nächster Monat") { calendar.showMonth(offset: 1) }
                .disabled(navigation.destination != .calendar)
        }
    }
}
