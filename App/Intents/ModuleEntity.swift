import AppIntents
import Foundation

/// A module as Shortcuts and Siri see it.
nonisolated struct ModuleEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Modul"
    static var defaultQuery: ModuleQuery { ModuleQuery() }

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

/// Finds active modules by ID or name.
nonisolated struct ModuleQuery: EntityStringQuery {
    @Dependency private var services: StudyAppIntentServices

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [ModuleEntity] {
        try services.activeModules().filter { identifiers.contains($0.id) }.map(Self.entity)
    }

    @MainActor
    func entities(matching string: String) async throws -> [ModuleEntity] {
        try services.activeModules().filter { $0.name.localizedCaseInsensitiveContains(string) }.map(Self.entity)
    }

    @MainActor
    func suggestedEntities() async throws -> [ModuleEntity] {
        try services.activeModules().map(Self.entity)
    }

    private static func entity(_ module: StudyModule) -> ModuleEntity {
        ModuleEntity(id: module.id, name: module.name)
    }
}
