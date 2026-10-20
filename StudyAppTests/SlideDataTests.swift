import Foundation
import SwiftData
import Testing
@testable import StudyApp

@MainActor
struct SlideDataTests {
    @Test func repositoryFiltersByModuleAndSupportsUpdateAndDelete() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        try withExtendedLifetime(container) {
            let repository = SwiftDataSlideDocumentRepository(context: container.mainContext)
            let moduleA = UUID()
            let moduleB = UUID()
            let documentA = SlideDocument(
                id: UUID(), moduleID: moduleA, title: "A",
                fileName: "a.pdf", pageCount: 3, importedAt: Date()
            )
            let documentB = SlideDocument(
                id: UUID(), moduleID: moduleB, title: "B",
                fileName: "b.pdf", pageCount: 4, importedAt: Date()
            )

            try repository.add(documentA)
            try repository.add(documentB)
            #expect(try repository.documents(forModule: moduleA).map(\.title) == ["A"])

            var renamed = documentA
            renamed.title = "A neu"
            try repository.update(renamed)
            #expect(try repository.documents(forModule: moduleA).first?.title == "A neu")

            try repository.delete(id: documentA.id)
            #expect(try repository.documents(forModule: moduleA).isEmpty)
            #expect(try repository.documents(forModule: moduleB).count == 1)
        }
    }

    @Test func localFileStorageCopiesAndRemoves() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "StudyAppTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let storage = try LocalFileStorage(
            baseDirectory: root.appending(path: "Slides", directoryHint: .isDirectory)
        )
        let source = root.appending(path: "source.pdf", directoryHint: .notDirectory)
        try Data("x".utf8).write(to: source)

        try storage.store(copyOf: source, as: "copy.pdf")
        #expect(FileManager.default.fileExists(atPath: storage.url(for: "copy.pdf").path))

        try storage.remove(fileName: "copy.pdf")
        #expect(!FileManager.default.fileExists(atPath: storage.url(for: "copy.pdf").path))

        // Erneutes Entfernen ist kein Fehler.
        try storage.remove(fileName: "copy.pdf")
    }

    @Test func inspectorRejectsNonPDFFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "StudyAppTests-\(UUID().uuidString).pdf", directoryHint: .notDirectory)
        try Data("das ist keine PDF".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(PDFKitInspector().pageCount(at: url) == nil)
    }
}
