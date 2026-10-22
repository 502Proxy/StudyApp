import Foundation

/// JSON encoding of the backup manifest and snapshot. Stable key order keeps archives diffable.
/// Dates are stored as seconds since 1970: ISO 8601 would drop fractional seconds, so a restored
/// timestamp would no longer equal the original.
enum BackupJSONCoding {
    static let manifestFileName = "manifest.json"
    static let snapshotFileName = "data.json"
    /// Folder inside the archive that mirrors the `FileStorage` layout.
    static let filesDirectoryName = "files"

    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw BackupError.invalidArchive
        }
    }
}
