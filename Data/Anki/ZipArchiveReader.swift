import Compression
import Foundation

/// Minimal reader for ZIP archives (as used by `.apkg`): stored and deflated entries, no ZIP64, no
/// encryption. Enough for Anki packages without pulling in a dependency.
struct ZipArchiveReader {
    enum ZipError: Error {
        case notAZipArchive
        case unsupportedEntry(String)
        case corruptEntry(String)
    }

    private struct Entry {
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private let bytes: [UInt8]
    private let entries: [String: Entry]

    var entryNames: Set<String> { Set(entries.keys) }

    init(data: Data) throws {
        bytes = [UInt8](data)
        entries = try Self.centralDirectory(bytes)
    }

    func data(for name: String) throws -> Data {
        guard let entry = entries[name] else { throw ZipError.corruptEntry(name) }
        let header = entry.localHeaderOffset
        guard Self.uint32(bytes, header) == 0x0403_4b50 else { throw ZipError.corruptEntry(name) }
        let start = header + 30 + Int(Self.uint16(bytes, header + 26)) + Int(Self.uint16(bytes, header + 28))
        let end = start + entry.compressedSize
        guard start >= 0, end <= bytes.count else { throw ZipError.corruptEntry(name) }
        let payload = Array(bytes[start..<end])
        switch entry.method {
        case 0:
            return Data(payload)
        case 8:
            return try Self.inflate(payload, expectedSize: entry.uncompressedSize, name: name)
        default:
            throw ZipError.unsupportedEntry(name)
        }
    }

    // MARK: Parsing

    private static func centralDirectory(_ bytes: [UInt8]) throws -> [String: Entry] {
        // The end-of-central-directory record is at most 22 + 65 535 (comment) bytes from the end.
        guard bytes.count >= 22 else { throw ZipError.notAZipArchive }
        let lowerBound = max(0, bytes.count - 22 - 65_535)
        guard let end = stride(from: bytes.count - 22, through: lowerBound, by: -1)
            .first(where: { uint32(bytes, $0) == 0x0605_4b50 }) else { throw ZipError.notAZipArchive }
        let count = Int(uint16(bytes, end + 10))
        var offset = Int(uint32(bytes, end + 16))
        var entries: [String: Entry] = [:]
        for _ in 0..<count {
            guard offset + 46 <= bytes.count, uint32(bytes, offset) == 0x0201_4b50 else { throw ZipError.notAZipArchive }
            let nameLength = Int(uint16(bytes, offset + 28))
            let extraLength = Int(uint16(bytes, offset + 30))
            let commentLength = Int(uint16(bytes, offset + 32))
            guard offset + 46 + nameLength <= bytes.count else { throw ZipError.notAZipArchive }
            guard let name = String(bytes: bytes[(offset + 46)..<(offset + 46 + nameLength)], encoding: .utf8) else {
                throw ZipError.notAZipArchive
            }
            entries[name] = Entry(
                method: uint16(bytes, offset + 10),
                compressedSize: Int(uint32(bytes, offset + 20)),
                uncompressedSize: Int(uint32(bytes, offset + 24)),
                localHeaderOffset: Int(uint32(bytes, offset + 42))
            )
            offset += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// `COMPRESSION_ZLIB` decodes raw DEFLATE, which is what ZIP stores.
    private static func inflate(_ payload: [UInt8], expectedSize: Int, name: String) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        var output = [UInt8](repeating: 0, count: expectedSize)
        let written = payload.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                compression_decode_buffer(
                    destination.baseAddress!, expectedSize, source.baseAddress!, payload.count, nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == expectedSize else { throw ZipError.corruptEntry(name) }
        return Data(output)
    }

    private static func uint16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        guard offset + 2 <= bytes.count else { return 0 }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func uint32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        return (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << (8 * UInt32($1)) }
    }
}
