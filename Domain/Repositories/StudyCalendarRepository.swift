import Foundation

@MainActor
protocol StudyCalendarRepository {
    func events() throws -> [StudyCalendarEvent]
    func sources() throws -> [CalendarSource]
    func save(source: CalendarSource) throws
    /// Gleicht die Termine einer Quelle mit dem übergebenen Stand ab: Neue werden angelegt, bekannte
    /// (über `externalID`) aktualisiert, nicht mehr enthaltene entfernt. Modulverknüpfungen bleiben erhalten.
    func replaceEvents(forSource sourceID: UUID, with events: [StudyCalendarEvent]) throws
    func updateModuleLink(eventID: UUID, moduleID: UUID?) throws
    /// Setzt die Modulzuordnung mehrerer Termine in einem Schritt, z. B. für eine ganze Veranstaltungsreihe.
    func updateModuleLinks(eventIDs: [UUID], moduleID: UUID?) throws
    /// Entfernt alle Verknüpfungen auf ein (gelöschtes) Modul. Die Termine selbst bleiben erhalten.
    func clearModuleLinks(forModule moduleID: UUID) throws
    func deleteSource(id: UUID) throws
}
