import Foundation
import SwiftData

enum Persistence {
    /// Persistente Modelle der App. Neue @Model-Typen werden hier zentral registriert.
    /// Existing module, slide and note data must remain intact when learning models are added.
    static let schema = Schema([ModuleRecord.self, SlideDocumentRecord.self, NoteRecord.self, FlashcardRecord.self, StudySheetRecord.self, CalendarSourceRecord.self, StudyCalendarEventRecord.self])

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
