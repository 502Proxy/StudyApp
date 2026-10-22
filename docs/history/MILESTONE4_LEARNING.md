# StudyApp – Lernbereich: Notizen, Karteikarten und Lernzettel

## Funktionsumfang

- **Notizübersicht:** Alle nicht-leeren Notizen der PDFs eines Moduls; Suche über Titel, Inhalt, Quelle und Seitenzahl; Auswahl mehrerer Notizen.
- **Notizen durchgehen:** Lesebereich mit Markdown-/KaTeX-Vorschau, Text- und LaTeX-Anzeige.
- **Karteikarten:** Manuell erstellbare und editierbare Frage-Antwort-Karten. Aus einer Notiz kann eine vorausgefüllte Karte erstellt und anschließend angepasst werden.
- **Spaced Repetition:** Fällige Karten zuerst; Bewertung „Nochmal“, „Schwer“, „Gut“ und „Einfach“ steuert das nächste Wiederholungsdatum. Die Terminierung ist SM-2-inspiriert: erfolgreiche Wiederholungen verlängern die Intervalle, schwierige Abrufe verkürzen sie; „Nochmal“ plant einen erneuten Versuch nach zehn Minuten.
- **Lernzettel:** Aus ausgewählten Notizen wird ein gespeicherter Markdown-Lernzettel mit Themenübersicht, vorhandenen Markdown-Überschriften, zusammengeführten Originalinhalten und automatisch formulierten Selbstkontrollfragen erstellt.
- **Datenintegrität:** Karteikarten und Lernzettel sind einem Modul zugeordnet und werden mit dem Modul gelöscht. Die Verknüpfung einer Karte auf eine Quellnotiz bleibt optional; die Karte bleibt auch ohne Quellnotiz nutzbar.

## Architektur

- `Domain/Entities`: `Flashcard`, `StudySheet` und `FlashcardReviewRating`.
- `Domain/Repositories`: Ports für Karteikarten und Lernzettel.
- `Domain/UseCases`: Validierung, CRUD-Anwendungsfälle, Spaced-Repetition-Terminierung und deterministische Lernzettel-Erstellung.
- `Data/SwiftData` und `Data/Repositories`: Persistenzadapter für SwiftData. Das Schema registriert die beiden neuen Modelle zusätzlich zu den vorhandenen; bestehende Notiz- und Folienmodelle bleiben erhalten.
- `Presentation/Learning`: `LearningViewModel` plus getrennte SwiftUI-Views für Notizübersicht, Karten, Karteneditor, Lernzettelerstellung und Lernzettelliste.
- `App/AppContainer.swift`: zentrale Abhängigkeitsverdrahtung.

Die Lernzettel-Erstellung benötigt keine externe API: Sie bewahrt vorhandene Notiztexte und organisiert sie. Sie führt **keine KI-Zusammenfassung** durch; Überschriften werden extrahiert und generische Selbstkontrollfragen ergänzt.

## In Xcode integrieren

Das bereitgestellte Archiv enthält Quellcode, aber kein `.xcodeproj` oder `.xcworkspace`. Bei einem bestehenden Xcode-Projekt deshalb neue Dateien zum passenden Target hinzufügen und die geänderten vorhandenen Dateien ersetzen.

### Neue Dateien für das App-Target

- `Domain/Entities/Flashcard.swift`
- `Domain/Entities/StudySheet.swift`
- `Domain/Repositories/FlashcardRepository.swift`
- `Domain/Repositories/StudySheetRepository.swift`
- `Domain/UseCases/FlashcardUseCases.swift`
- `Domain/UseCases/StudySheetUseCases.swift`
- `Data/SwiftData/FlashcardRecord.swift`
- `Data/SwiftData/StudySheetRecord.swift`
- `Data/Repositories/SwiftDataFlashcardRepository.swift`
- `Data/Repositories/SwiftDataStudySheetRepository.swift`
- `Presentation/Learning/LearningViewModel.swift`
- `Presentation/Learning/NotesOverviewView.swift`
- `Presentation/Learning/FlashcardsView.swift`
- `Presentation/Learning/FlashcardEditorSheet.swift`
- `Presentation/Learning/StudySheetsView.swift`
- `Presentation/Learning/StudySheetCreateSheet.swift`

### Geänderte Dateien für das App-Target

- `App/AppContainer.swift`
- `App/StudyAppApp.swift`
- `Data/SwiftData/Persistence.swift`
- `Domain/UseCases/ModuleUseCases.swift`
- `Presentation/RootView.swift`
- `Presentation/Modules/ModuleDetailView.swift`
- `Presentation/Modules/ModulesViewModel.swift`

### Neue Dateien für das Test-Target

- `StudyAppTests/LearningUseCaseTests.swift`
- `StudyAppTests/LearningDataTests.swift`

Auch die bestehenden Tests, welche `DeleteModuleUseCase` erzeugen, wurden um Test-Repositories für Lernmaterial ergänzt.

## Prüfstatus

Die Domain-Dateien lassen sich mit Swift 6.2 unter Linux typprüfen und alle Swift-Dateien bestehen die Syntaxprüfung. SwiftUI-/SwiftData-Builds und persistenzbasierte Tests müssen auf macOS in Xcode ausgeführt werden, da Linux diese Apple-Frameworks nicht bereitstellt. Ein vollständiger App-Build wurde daher nicht behauptet.
