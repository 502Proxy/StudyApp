import Foundation

@MainActor
struct ListSlideDocumentsUseCase {
    let repository: any SlideDocumentRepository

    /// Natürlich sortiert, damit "Folie 2" vor "Folie 10" steht.
    func callAsFunction(moduleID: UUID) throws -> [SlideDocument] {
        try repository.documents(forModule: moduleID).sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }
}

@MainActor
struct ImportSlideDocumentUseCase {
    let repository: any SlideDocumentRepository
    let storage: any FileStorage
    let inspector: any PDFInspector

    /// Kopiert die PDF in den App-Speicher und legt den Datensatz an.
    /// Schlägt ein Schritt fehl, wird die kopierte Datei wieder entfernt.
    @discardableResult
    func callAsFunction(from sourceURL: URL, moduleID: UUID) throws -> SlideDocument {
        try importDocument(
            moduleID: moduleID,
            title: sourceURL.deletingPathExtension().lastPathComponent,
            displayName: sourceURL.lastPathComponent
        ) { fileName in
            try storage.store(copyOf: sourceURL, as: fileName)
        }
    }

    /// Legt eine heruntergeladene PDF an, z. B. aus Stud.IP.
    @discardableResult
    func callAsFunction(
        data: Data,
        title: String,
        moduleID: UUID,
        remoteID: String? = nil,
        remoteVersion: String? = nil
    ) throws -> SlideDocument {
        try importDocument(
            moduleID: moduleID, title: title, displayName: title,
            remoteID: remoteID, remoteVersion: remoteVersion
        ) { fileName in
            try storage.write(data, as: fileName)
        }
    }

    private func importDocument(
        moduleID: UUID,
        title: String,
        displayName: String,
        remoteID: String? = nil,
        remoteVersion: String? = nil,
        writeFile: (String) throws -> Void
    ) throws -> SlideDocument {
        let id = UUID()
        let fileName = "\(id.uuidString).pdf"

        try writeFile(fileName)
        do {
            guard let pages = inspector.pageCount(at: storage.url(for: fileName)), pages > 0 else {
                throw SlideError.invalidPDF(displayName)
            }

            let cleanTitle = title.trimmed
            let document = SlideDocument(
                id: id,
                moduleID: moduleID,
                title: cleanTitle.isEmpty ? "Folien" : cleanTitle,
                fileName: fileName,
                pageCount: pages,
                importedAt: Date(),
                remoteID: remoteID,
                remoteVersion: remoteVersion
            )
            try repository.add(document)
            return document
        } catch {
            try? storage.remove(fileName: fileName)
            throw error
        }
    }
}

@MainActor
struct RenameSlideDocumentUseCase {
    let repository: any SlideDocumentRepository

    @discardableResult
    func callAsFunction(_ document: SlideDocument, to title: String) throws -> SlideDocument {
        let cleanTitle = title.trimmed
        guard !cleanTitle.isEmpty else { throw SlideError.emptyTitle }

        var updated = document
        updated.title = cleanTitle
        try repository.update(updated)
        return updated
    }
}

/// Deletes a slide document together with its PDF file and all of its notes.
@MainActor
struct DeleteSlideDocumentUseCase {
    let repository: any SlideDocumentRepository
    let noteRepository: any NoteRepository
    let storage: any FileStorage

    func callAsFunction(_ document: SlideDocument) throws {
        try repository.delete(id: document.id)
        // Eine übrig gebliebene Datei ist harmlos, der Datensatz ist maßgeblich.
        try? storage.remove(fileName: document.fileName)
        // Runs last on purpose: a failure here must not keep the PDF file around.
        try DeleteNoteUseCase(repository: noteRepository)(slideDocumentID: document.id)
    }
}
