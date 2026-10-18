import Foundation

/// Zero-based cell coordinates, displayed in A1 notation.
public struct CellAddress: Hashable, Comparable, Sendable, CustomStringConvertible {
    public static let maxRows = 1_048_576
    public static let maxColumns = 16_384

    public var row: Int
    public var column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    /// Parses `B12` or `$B$12`.
    public init?(a1 text: String) {
        guard let reference = A1Reference.parse(text) else { return nil }
        self = reference.address
    }

    public var a1: String { CellAddress.columnName(column) + String(row + 1) }
    public var description: String { a1 }

    public var isValid: Bool {
        row >= 0 && column >= 0 && row < Self.maxRows && column < Self.maxColumns
    }

    public func offset(rows: Int, columns: Int) -> CellAddress {
        CellAddress(row: row + rows, column: column + columns)
    }

    public func clamped() -> CellAddress {
        CellAddress(row: min(max(row, 0), Self.maxRows - 1), column: min(max(column, 0), Self.maxColumns - 1))
    }

    public static func < (lhs: CellAddress, rhs: CellAddress) -> Bool {
        (lhs.row, lhs.column) < (rhs.row, rhs.column)
    }

    public static func columnName(_ index: Int) -> String {
        var n = index + 1
        var letters: [Character] = []
        while n > 0 {
            let remainder = (n - 1) % 26
            letters.append(Character(UnicodeScalar(UInt8(65 + remainder))))
            n = (n - 1) / 26
        }
        return String(letters.reversed())
    }

    public static func columnIndex<S: StringProtocol>(_ letters: S) -> Int? {
        guard !letters.isEmpty, letters.count <= 3 else { return nil }
        var value = 0
        for scalar in letters.unicodeScalars {
            switch scalar.value {
            case 65...90: value = value * 26 + Int(scalar.value - 64)
            case 97...122: value = value * 26 + Int(scalar.value - 96)
            default: return nil
            }
        }
        return value - 1 < maxColumns ? value - 1 : nil
    }
}

/// A rectangular block of cells, normalized so `start` is the top-left corner.
public struct CellRange: Hashable, Sendable, CustomStringConvertible {
    public let start: CellAddress
    public let end: CellAddress

    public init(_ a: CellAddress, _ b: CellAddress) {
        start = CellAddress(row: min(a.row, b.row), column: min(a.column, b.column))
        end = CellAddress(row: max(a.row, b.row), column: max(a.column, b.column))
    }

    public var rowCount: Int { end.row - start.row + 1 }
    public var columnCount: Int { end.column - start.column + 1 }
    public var cellCount: Int { rowCount * columnCount }

    public func contains(_ address: CellAddress) -> Bool {
        (start.row...end.row).contains(address.row) && (start.column...end.column).contains(address.column)
    }

    /// Addresses in row-major order.
    public var addresses: [CellAddress] {
        (start.row...end.row).flatMap { row in
            (start.column...end.column).map { CellAddress(row: row, column: $0) }
        }
    }

    public var a1: String { start == end ? start.a1 : "\(start.a1):\(end.a1)" }
    public var description: String { a1 }
}

/// A cell reference as written in a formula, including its `$` anchors.
struct A1Reference: Equatable {
    var address: CellAddress
    var absoluteColumn: Bool
    var absoluteRow: Bool

    static func parse<S: StringProtocol>(_ text: S) -> A1Reference? {
        let chars = Array(text)
        var i = 0
        var absoluteColumn = false
        var absoluteRow = false
        if i < chars.count, chars[i] == "$" { absoluteColumn = true; i += 1 }
        let lettersStart = i
        while i < chars.count, chars[i].isASCII, chars[i].isLetter { i += 1 }
        guard let column = CellAddress.columnIndex(String(chars[lettersStart..<i])) else { return nil }
        if i < chars.count, chars[i] == "$" { absoluteRow = true; i += 1 }
        let digits = chars[i...]
        guard !digits.isEmpty, digits.count <= 7, digits.first != "0",
              digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let rowNumber = Int(String(digits)), rowNumber <= CellAddress.maxRows else { return nil }
        return A1Reference(
            address: CellAddress(row: rowNumber - 1, column: column),
            absoluteColumn: absoluteColumn,
            absoluteRow: absoluteRow
        )
    }

    func formatted() -> String {
        (absoluteColumn ? "$" : "") + CellAddress.columnName(address.column)
            + (absoluteRow ? "$" : "") + String(address.row + 1)
    }

    /// A whole-row reference such as `$3`, used in `$3:$5`; plain row numbers lex as numbers.
    static func parseRow<S: StringProtocol>(_ text: S) -> Int? {
        let digits = text.hasPrefix("$") ? text.dropFirst() : text[...]
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let row = Int(digits),
              row >= 1, row <= CellAddress.maxRows else { return nil }
        return row - 1
    }

    /// A whole-column reference such as `C` or `$C`, used in `C:C`.
    static func parseColumn<S: StringProtocol>(_ text: S) -> (column: Int, absolute: Bool)? {
        let absolute = text.hasPrefix("$")
        guard let column = CellAddress.columnIndex(absolute ? text.dropFirst() : text[...]) else { return nil }
        return (column, absolute)
    }
}
