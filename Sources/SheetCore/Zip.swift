import Compression
import Foundation

public enum ZipError: Error, LocalizedError {
    case notAZip
    case corrupt(String)
    case unsupported(String)
    case missingEntry(String)

    public var errorDescription: String? {
        switch self {
        case .notAZip: "The file is not a ZIP package."
        case .corrupt(let detail): "The ZIP package is damaged: \(detail)."
        case .unsupported(let detail): "Unsupported ZIP feature: \(detail)."
        case .missingEntry(let name): "The package has no \(name) part."
        }
    }
}

/// Reads stored and deflated entries of a ZIP archive held in memory.
struct ZipArchive {
    struct Entry {
        let method: UInt16
        let crc: UInt32
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    /// Upper bound for one decompressed part; protects against ZIP bombs.
    static let maxEntrySize = 512 * 1024 * 1024

    private let bytes: [UInt8]
    private(set) var entries: [String: Entry] = [:]

    init(data: Data) throws {
        bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw ZipError.notAZip }
        let lowest = max(0, bytes.count - 22 - 65_535)
        guard let end = stride(from: bytes.count - 22, through: lowest, by: -1).first(where: { u32($0) == 0x0605_4B50 }) else {
            throw ZipError.notAZip
        }
        let count = Int(u16(end + 10))
        let directoryOffset = Int(u32(end + 16))
        guard u32(end + 16) != 0xFFFF_FFFF, u16(end + 10) != 0xFFFF else { throw ZipError.unsupported("ZIP64") }

        var p = directoryOffset
        for _ in 0..<count {
            guard p + 46 <= bytes.count, u32(p) == 0x0201_4B50 else { throw ZipError.corrupt("bad central directory") }
            let nameLength = Int(u16(p + 28))
            let extraLength = Int(u16(p + 30))
            let commentLength = Int(u16(p + 32))
            guard p + 46 + nameLength <= bytes.count else { throw ZipError.corrupt("truncated entry name") }
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + nameLength)], as: UTF8.self)
            entries[Self.key(name)] = Entry(
                method: u16(p + 10),
                crc: u32(p + 16),
                compressedSize: Int(u32(p + 20)),
                uncompressedSize: Int(u32(p + 24)),
                localHeaderOffset: Int(u32(p + 42))
            )
            p += 46 + nameLength + extraLength + commentLength
        }
    }

    /// Package part names compare case-insensitively; some writers also use backslashes.
    private static func key(_ name: String) -> String {
        name.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    func contains(_ name: String) -> Bool { entries[Self.key(name)] != nil }

    func data(_ name: String) throws -> Data {
        guard let entry = entries[Self.key(name)] else { throw ZipError.missingEntry(name) }
        let header = entry.localHeaderOffset
        guard header + 30 <= bytes.count, u32(header) == 0x0403_4B50 else { throw ZipError.corrupt("bad local header for \(name)") }
        let start = header + 30 + Int(u16(header + 26)) + Int(u16(header + 28))
        guard start + entry.compressedSize <= bytes.count else { throw ZipError.corrupt("truncated \(name)") }
        guard entry.uncompressedSize <= Self.maxEntrySize else { throw ZipError.unsupported("\(name) is larger than 512 MB") }
        let compressed = bytes[start..<(start + entry.compressedSize)]

        let output: [UInt8]
        switch entry.method {
        case 0:
            output = Array(compressed)
        case 8:
            output = try Deflate.decompress(compressed, size: entry.uncompressedSize)
        default:
            throw ZipError.unsupported("compression method \(entry.method)")
        }
        guard CRC32.checksum(output) == entry.crc else { throw ZipError.corrupt("checksum mismatch in \(name)") }
        return Data(output)
    }

    private func u16(_ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private func u32(_ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }
}

/// Writes a ZIP archive, deflating entries when that makes them smaller.
struct ZipWriter {
    private var body: [UInt8] = []
    private var directory: [UInt8] = []
    private var count = 0

    mutating func add(_ name: String, _ text: String) {
        add(name, Array(text.utf8))
    }

    mutating func add(_ name: String, _ content: [UInt8]) {
        let nameBytes = Array(name.utf8)
        let crc = CRC32.checksum(content)
        let deflated = Deflate.compress(content)
        let (method, stored): (UInt16, [UInt8]) = deflated.map { (8, $0) } ?? (0, content)
        let offset = body.count
        // Fixed timestamp 1980-01-01 keeps output deterministic.
        let (time, date): (UInt16, UInt16) = (0, 0x21)

        body += le32(0x0403_4B50) + le16(20) + le16(0x0800) + le16(method) + le16(time) + le16(date)
        body += le32(crc) + le32(UInt32(stored.count)) + le32(UInt32(content.count))
        body += le16(UInt16(nameBytes.count)) + le16(0) + nameBytes + stored

        directory += le32(0x0201_4B50) + le16(20) + le16(20) + le16(0x0800) + le16(method) + le16(time) + le16(date)
        directory += le32(crc) + le32(UInt32(stored.count)) + le32(UInt32(content.count))
        directory += le16(UInt16(nameBytes.count)) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(UInt32(offset))
        directory += nameBytes
        count += 1
    }

    func finish() -> Data {
        var output = body + directory
        output += le32(0x0605_4B50) + le16(0) + le16(0) + le16(UInt16(count)) + le16(UInt16(count))
        output += le32(UInt32(directory.count)) + le32(UInt32(body.count)) + le16(0)
        return Data(output)
    }

    private func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
    private func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> ($0 * 8)) & 0xFF) } }
}

/// Raw DEFLATE (RFC 1951) through Apple's Compression framework, whose ZLIB codec omits the zlib header.
enum Deflate {
    static func decompress(_ input: ArraySlice<UInt8>, size: Int) throws -> [UInt8] {
        guard size > 0 else { return [] }
        var output = [UInt8](repeating: 0, count: size)
        let written = input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                compression_decode_buffer(destination.baseAddress!, size, source.baseAddress!, source.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw ZipError.corrupt("inflated size mismatch") }
        return output
    }

    /// Returns nil when compression would not save space.
    static func compress(_ input: [UInt8]) -> [UInt8]? {
        guard input.count > 64 else { return nil }
        var output = [UInt8](repeating: 0, count: input.count)
        let written = input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                compression_encode_buffer(destination.baseAddress!, input.count, source.baseAddress!, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0, written < input.count else { return nil }
        return Array(output[0..<written])
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { n in
        (0..<8).reduce(UInt32(n)) { c, _ in c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
    }

    static func checksum<C: Collection>(_ bytes: C) -> UInt32 where C.Element == UInt8 {
        ~bytes.reduce(UInt32.max) { crc, byte in table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
    }
}
