import Foundation
import SQLite3
import Testing
@testable import StudyApp

/// Builds `.apkg` fixtures: a SQLite collection with a `notes` table inside a stored ZIP.
private enum AnkiFixture {
    static func collection(notes: [(fields: [String], tags: String)]) throws -> Data {
        let url = FileManager.default.temporaryDirectory.appending(path: "anki-fixture-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        var handle: OpaquePointer?
        try #require(sqlite3_open(url.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        try #require(sqlite3_exec(handle, "CREATE TABLE notes (id INTEGER PRIMARY KEY, flds TEXT, tags TEXT)", nil, nil, nil) == SQLITE_OK)
        for (index, note) in notes.enumerated() {
            let fields = note.fields.joined(separator: "\u{1f}").replacingOccurrences(of: "'", with: "''")
            let sql = "INSERT INTO notes VALUES (\(index + 1), '\(fields)', '\(note.tags)')"
            try #require(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
        }
        sqlite3_close(handle)
        handle = nil
        return try Data(contentsOf: url)
    }

    /// A ZIP with stored (uncompressed) entries; the reader does not check CRCs.
    static func zip(_ entries: [(name: String, data: Data)]) -> Data {
        var archive = Data()
        var central = Data()
        for entry in entries {
            let offset = UInt32(archive.count)
            let name = Data(entry.name.utf8)
            archive += le32(0x0403_4b50) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0)
            archive += le32(UInt32(entry.data.count)) + le32(UInt32(entry.data.count)) + le16(UInt16(name.count)) + le16(0)
            archive += name + entry.data
            central += le32(0x0201_4b50) + le16(20) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0)
            central += le32(UInt32(entry.data.count)) + le32(UInt32(entry.data.count))
            central += le16(UInt16(name.count)) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(offset) + name
        }
        let centralOffset = UInt32(archive.count)
        archive += central
        archive += le32(0x0605_4b50) + le16(0) + le16(0) + le16(UInt16(entries.count)) + le16(UInt16(entries.count))
        archive += le32(UInt32(central.count)) + le32(centralOffset) + le16(0)
        return archive
    }

    private static func le16(_ value: UInt16) -> Data { Data([UInt8(value & 0xFF), UInt8(value >> 8)]) }
    private static func le32(_ value: UInt32) -> Data { Data((0..<4).map { UInt8((value >> (8 * $0)) & 0xFF) }) }
}

@MainActor
struct AnkiPackageReaderTests {
    private func write(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "deck-\(UUID().uuidString).apkg")
        try data.write(to: url)
        return url
    }

    @Test func readsNotesFromALegacyCollection() throws {
        let collection = try AnkiFixture.collection(notes: [
            (["Was ist <b>Stetigkeit</b>?", "Kein Sprung im Graphen<br>[sound:x.mp3]"], " Analysis_I "),
            (["Nur ein Feld"], ""),
        ])
        let url = try write(AnkiFixture.zip([("collection.anki21", collection), ("media", Data("{}".utf8))]))
        defer { try? FileManager.default.removeItem(at: url) }

        let cards = try AnkiPackageReader().cards(from: url)

        #expect(cards == [ExchangedFlashcard(front: "Was ist Stetigkeit?", back: "Kein Sprung im Graphen", tags: ["Analysis_I"])])
    }

    @Test func reportsTheNewPackageFormat() throws {
        let url = try write(AnkiFixture.zip([
            ("collection.anki2", try AnkiFixture.collection(notes: [(["Bitte Anki aktualisieren", ""], "")])),
            ("collection.anki21b", Data([0x28, 0xB5, 0x2F, 0xFD])),
        ]))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: FlashcardExchangeError.newPackageFormat) { try AnkiPackageReader().cards(from: url) }
    }

    @Test func rejectsFilesThatAreNoArchive() throws {
        let url = try write(Data("kein zip".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: FlashcardExchangeError.unreadablePackage) { try AnkiPackageReader().cards(from: url) }
    }

    @Test func fileReaderChoosesTheFormatByExtension() throws {
        let text = FileManager.default.temporaryDirectory.appending(path: "deck-\(UUID().uuidString).txt")
        try "Frage\tAntwort\n".write(to: text, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: text) }

        #expect(try AnkiFileReader().cards(from: text) == [ExchangedFlashcard(front: "Frage", back: "Antwort")])
        #expect(throws: FlashcardExchangeError.unsupportedFile) {
            try AnkiFileReader().cards(from: URL(filePath: "/tmp/deck.pdf"))
        }
    }
}
