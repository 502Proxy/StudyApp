import Foundation
import SQLite3

/// Reads the notes of an Anki package (`.apkg`): a ZIP with the collection as SQLite database.
/// Supports the legacy collections `collection.anki21` and `collection.anki2`; packages that only
/// contain the newer compressed `collection.anki21b` are reported as such.
struct AnkiPackageReader {
    func cards(from url: URL) throws -> [ExchangedFlashcard] {
        let archive: ZipArchiveReader
        do {
            archive = try ZipArchiveReader(data: try Data(contentsOf: url))
        } catch {
            throw FlashcardExchangeError.unreadablePackage
        }
        let names = archive.entryNames
        // A package with anki21b but no anki21 only carries a „please update Anki“ note in anki2.
        let collectionName: String
        if names.contains("collection.anki21") {
            collectionName = "collection.anki21"
        } else if names.contains("collection.anki21b") {
            throw FlashcardExchangeError.newPackageFormat
        } else if names.contains("collection.anki2") {
            collectionName = "collection.anki2"
        } else {
            throw FlashcardExchangeError.unreadablePackage
        }

        let database = FileManager.default.temporaryDirectory
            .appending(path: "StudyApp-anki-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: database) }
        do {
            try archive.data(for: collectionName).write(to: database)
        } catch {
            throw FlashcardExchangeError.unreadablePackage
        }
        return try Self.notes(inDatabaseAt: database)
    }

    /// Fields are separated by U+001F; the first is the front, the second the back.
    static func notes(inDatabaseAt url: URL) throws -> [ExchangedFlashcard] {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let handle else {
            sqlite3_close(handle)
            throw FlashcardExchangeError.unreadablePackage
        }
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT flds, tags FROM notes ORDER BY id", -1, &statement, nil) == SQLITE_OK else {
            throw FlashcardExchangeError.unreadablePackage
        }
        defer { sqlite3_finalize(statement) }
        var cards: [ExchangedFlashcard] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let fields = text(statement, 0).components(separatedBy: "\u{1f}")
            guard fields.count >= 2 else { continue }
            cards.append(ExchangedFlashcard(
                front: AnkiFieldText.plainText(fields[0]),
                back: AnkiFieldText.plainText(fields[1]),
                tags: text(statement, 1).split(separator: " ").map(String.init)
            ))
        }
        return cards
    }

    private static func text(_ statement: OpaquePointer?, _ column: Int32) -> String {
        sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
    }
}
