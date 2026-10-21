import Foundation

/// Katalog der Stud.IP-Dateien je Modul. Die Dateien selbst liegen im `FileStorage`.
@MainActor
protocol CourseFileRepository {
    func files(forModule moduleID: UUID) throws -> [CourseFile]
    /// Übernimmt den aktuellen Stand aus Stud.IP. Bekannte Dateien behalten ihre lokale Kopie,
    /// nicht mehr vorhandene werden entfernt und zurückgegeben, damit ihre Kopien gelöscht werden können.
    @discardableResult
    func replaceCatalog(forModule moduleID: UUID, with files: [CourseFile]) throws -> [CourseFile]
    func update(_ file: CourseFile) throws
    /// Entfernt den ganzen Katalog eines Moduls und gibt die entfernten Einträge zurück.
    @discardableResult
    func deleteFiles(forModule moduleID: UUID) throws -> [CourseFile]
}
