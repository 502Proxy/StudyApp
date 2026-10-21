import Foundation
import SwiftData

@MainActor
final class SwiftDataCourseFileRepository: CourseFileRepository {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func files(forModule moduleID: UUID) throws -> [CourseFile] {
        try records(forModule: moduleID).map { $0.toDomain() }
    }

    func replaceCatalog(forModule moduleID: UUID, with files: [CourseFile]) throws -> [CourseFile] {
        var stored = Dictionary(try records(forModule: moduleID).map { ($0.remoteID, $0) }, uniquingKeysWith: { first, _ in first })
        for file in files {
            if let record = stored.removeValue(forKey: file.remoteID) {
                record.applyRemote(file)
            } else {
                context.insert(CourseFileRecord(file))
            }
        }
        let removed = stored.values.map { $0.toDomain() }
        for record in stored.values {
            context.delete(record)
        }
        try context.save()
        return removed
    }

    func update(_ file: CourseFile) throws {
        let key = file.id
        let descriptor = FetchDescriptor<CourseFileRecord>(predicate: #Predicate { $0.key == key })
        guard let record = try context.fetch(descriptor).first else { return }
        record.applyRemote(file)
        record.localFileName = file.localFileName
        record.downloadedVersion = file.downloadedVersion
        try context.save()
    }

    func deleteFiles(forModule moduleID: UUID) throws -> [CourseFile] {
        let records = try records(forModule: moduleID)
        guard !records.isEmpty else { return [] }
        let removed = records.map { $0.toDomain() }
        for record in records {
            context.delete(record)
        }
        try context.save()
        return removed
    }

    private func records(forModule moduleID: UUID) throws -> [CourseFileRecord] {
        let descriptor = FetchDescriptor<CourseFileRecord>(predicate: #Predicate { $0.moduleID == moduleID })
        return try context.fetch(descriptor)
    }
}
