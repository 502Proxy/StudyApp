import Foundation
import SwiftData
import Testing
@testable import StudyApp

@MainActor
struct SwiftDataModuleRepositoryTests {
    @Test func roundTripAddUpdateDelete() throws {
        // Der Container muss während des Tests am Leben bleiben.
        let container = try Persistence.makeContainer(inMemory: true)
        try withExtendedLifetime(container) {
            let repository = SwiftDataModuleRepository(context: container.mainContext)
            let module = StudyModule(
                id: UUID(), name: "Analysis I", code: "MAT101",
                color: .blue, createdAt: Date()
            )

            try repository.add(module)
            #expect(try repository.all().map(\.name) == ["Analysis I"])

            var changed = module
            changed.name = "Analysis II"
            changed.color = .orange
            try repository.update(changed)

            let stored = try #require(try repository.all().first)
            #expect(stored.name == "Analysis II")
            #expect(stored.color == .orange)

            try repository.delete(id: module.id)
            #expect(try repository.all().isEmpty)
        }
    }

    @Test func updateUnknownModuleThrowsNotFound() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        withExtendedLifetime(container) {
            let repository = SwiftDataModuleRepository(context: container.mainContext)
            let ghost = StudyModule(
                id: UUID(), name: "Ghost", code: "",
                color: .violet, createdAt: Date()
            )

            #expect(throws: ModuleError.notFound) {
                try repository.update(ghost)
            }
        }
    }
}
