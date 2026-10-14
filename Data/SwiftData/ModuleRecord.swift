import Foundation
import SwiftData

/// SwiftData-Modell. Bleibt in der Data-Schicht, die Domain sieht nur `StudyModule`.
@Model
final class ModuleRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var code: String
    var colorRaw: String
    var createdAt: Date

    init(id: UUID, name: String, code: String, colorRaw: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.code = code
        self.colorRaw = colorRaw
        self.createdAt = createdAt
    }
}

extension ModuleRecord {
    convenience init(_ module: StudyModule) {
        self.init(
            id: module.id,
            name: module.name,
            code: module.code,
            colorRaw: module.color.rawValue,
            createdAt: module.createdAt
        )
    }

    func toDomain() -> StudyModule {
        StudyModule(
            id: id,
            name: name,
            code: code,
            color: ModuleColor(rawValue: colorRaw) ?? .violet,
            createdAt: createdAt
        )
    }

    func apply(_ module: StudyModule) {
        name = module.name
        code = module.code
        colorRaw = module.color.rawValue
    }
}
