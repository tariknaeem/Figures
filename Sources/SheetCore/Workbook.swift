import Foundation

/// An AutoFilter: a header row plus data rows, with the values each column may show.
public struct AutoFilter: Equatable, Sendable {
    /// Header row first, then the data rows.
    public var range: CellRange
    /// Displayed texts allowed per sheet column; unlisted columns are unfiltered. `""` means blanks.
    public var allowedValues: [Int: Set<String>] = [:]

    public init(range: CellRange, allowedValues: [Int: Set<String>] = [:]) {
        self.range = range
        self.allowedValues = allowedValues
    }

    public var dataRows: ClosedRange<Int>? {
        range.rowCount > 1 ? (range.start.row + 1)...range.end.row : nil
    }
}

public struct Sheet: Equatable, Sendable {
    public var name: String
    /// What the user typed, keyed by cell. Formulas start with `=`.
    public var cells: [CellAddress: String] = [:]
    public var formats: [CellAddress: CellFormat] = [:]
    /// Interactive controls shown in cells: checkboxes, star ratings, pop-up menus, steppers and sliders.
    public var controls: [CellAddress: CellControl] = [:]
    /// Charts, text boxes, shapes and images floating over the cells, back to front.
    public var canvas: [CanvasObject] = []
    /// Custom column widths in points.
    public var columnWidths: [Int: Double] = [:]
    /// Width of columns without a custom width, in points (Excel's 8.43 characters).
    public var defaultColumnWidth = 64.0
    /// Custom row heights in Excel points.
    public var rowHeights: [Int: Double] = [:]
    /// Height of rows without a custom height, in Excel points.
    public var defaultRowHeight = 15.0
    /// Rows hidden by the user; rows hidden by the filter are computed from `filter`.
    public var hiddenRows: Set<Int> = []
    public var hiddenColumns: Set<Int> = []
    /// Merged areas; each shows the value and format of its top-left cell.
    public var merges: [CellRange] = []
    /// Rules in priority order, highest first.
    public var conditionalFormats: [ConditionalFormat] = []
    public var filter: AutoFilter?
    /// Number of top rows that stay visible while scrolling.
    public var frozenRows = 0
    public var showGridlines = true

    /// The merged area containing an address, if any.
    public func merge(containing address: CellAddress) -> CellRange? {
        merges.first { $0.contains(address) }
    }

    public init(name: String) {
        self.name = name
    }

    public var maxRow: Int? { cells.keys.map(\.row).max() }
    public var maxColumn: Int? { cells.keys.map(\.column).max() }

    public mutating func setInput(_ raw: String, at address: CellAddress) {
        if raw.isEmpty {
            cells.removeValue(forKey: address)
        } else {
            cells[address] = raw
        }
    }

    public mutating func setFormat(_ format: CellFormat, at address: CellAddress) {
        if format.isDefault {
            formats.removeValue(forKey: address)
        } else {
            formats[address] = format
        }
    }

    /// The block of filled cells connected to an address, like Excel's current region.
    public func currentRegion(around address: CellAddress) -> CellRange {
        func occupied(_ row: Int, _ column: Int) -> Bool {
            row >= 0 && column >= 0 && cells[CellAddress(row: row, column: column)] != nil
        }
        var (top, bottom, left, right) = (address.row, address.row, address.column, address.column)
        var grew = true
        while grew {
            grew = false
            if top > 0, (left - 1...right + 1).contains(where: { occupied(top - 1, $0) }) { top -= 1; grew = true }
            if (left - 1...right + 1).contains(where: { occupied(bottom + 1, $0) }) { bottom += 1; grew = true }
            if left > 0, (top - 1...bottom + 1).contains(where: { occupied($0, left - 1) }) { left -= 1; grew = true }
            if (top - 1...bottom + 1).contains(where: { occupied($0, right + 1) }) { right += 1; grew = true }
        }
        return CellRange(CellAddress(row: top, column: left), CellAddress(row: bottom, column: right))
    }
}

/// A named formula or reference, such as `TaxRate` for `Settings!$B$2`.
public struct DefinedName: Equatable, Sendable {
    public var name: String
    /// The definition without the leading `=`.
    public var formula: String
    /// The sheet the name is local to; nil for workbook-wide names.
    public var scope: Int?

    public init(name: String, formula: String, scope: Int? = nil) {
        self.name = name
        self.formula = formula
        self.scope = scope
    }
}

public struct Workbook: Equatable, Sendable {
    public var sheets: [Sheet] {
        didSet { version = UUID() }
    }

    public var definedNames: [DefinedName] = [] {
        didSet { version = UUID() }
    }

    /// The font of cells whose format names no font, as styles.xml's first font.
    public var defaultFontName = "Calibri" {
        didSet { version = UUID() }
    }
    public var defaultFontSize = 11.0 {
        didSet { version = UUID() }
    }

    /// Changes on every edit, so cached calculations can tell workbooks apart cheaply.
    public private(set) var version = UUID()

    public init(sheets: [Sheet] = [Sheet(name: "Sheet1")]) {
        self.sheets = sheets.isEmpty ? [Sheet(name: "Sheet1")] : sheets
    }

    public func sheetIndex(named name: String) -> Int? {
        sheets.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    @discardableResult
    public mutating func addSheet() -> Int {
        var number = sheets.count + 1
        while sheetIndex(named: "Sheet\(number)") != nil { number += 1 }
        sheets.append(Sheet(name: "Sheet\(number)"))
        return sheets.count - 1
    }

    public mutating func removeSheet(at index: Int) {
        guard sheets.count > 1, sheets.indices.contains(index) else { return }
        sheets.remove(at: index)
    }

    /// Renames a sheet using Excel's naming rules; returns false if the name is unusable or taken.
    @discardableResult
    public mutating func renameSheet(at index: Int, to proposed: String) -> Bool {
        let name = Workbook.sanitizedSheetName(proposed)
        guard !name.isEmpty, sheets.indices.contains(index) else { return false }
        if let existing = sheetIndex(named: name), existing != index { return false }
        sheets[index].name = name
        return true
    }

    /// Excel sheet names are at most 31 characters, without `[]:*?/\` or edge apostrophes.
    public static func sanitizedSheetName(_ proposed: String) -> String {
        let forbidden = Set("[]:*?/\\")
        let filtered = String(proposed.filter { !forbidden.contains($0) }.prefix(31))
        return filtered.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "'")))
    }
}
