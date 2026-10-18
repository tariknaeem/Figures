import Foundation

/// Inserting or deleting whole rows or columns of one sheet.
public enum StructuralChange: Equatable, Sendable {
    case insertRows(at: Int, count: Int)
    case deleteRows(at: Int, count: Int)
    case insertColumns(at: Int, count: Int)
    case deleteColumns(at: Int, count: Int)

    var affectsRows: Bool {
        switch self {
        case .insertRows, .deleteRows: true
        case .insertColumns, .deleteColumns: false
        }
    }

    private var limit: Int { affectsRows ? CellAddress.maxRows : CellAddress.maxColumns }

    /// The new position of an index, or nil if it was deleted or pushed off the sheet.
    func map(_ index: Int) -> Int? {
        switch self {
        case .insertRows(let at, let count), .insertColumns(let at, let count):
            let moved = index >= at ? index + count : index
            return moved < limit ? moved : nil
        case .deleteRows(let at, let count), .deleteColumns(let at, let count):
            if index < at { return index }
            return index < at + count ? nil : index - count
        }
    }

    /// New bounds of a span; deleting part of it shrinks it, deleting all of it returns nil.
    func mapSpan(_ start: Int, _ end: Int) -> (start: Int, end: Int)? {
        switch self {
        case .insertRows, .insertColumns:
            guard let s = map(start) else { return nil }
            return (s, map(end) ?? limit - 1)
        case .deleteRows(let at, let count), .deleteColumns(let at, let count):
            let s = start < at ? start : (start < at + count ? at : start - count)
            let e = end < at ? end : (end < at + count ? at - 1 : end - count)
            return e >= s ? (s, e) : nil
        }
    }

    func adjust(_ address: CellAddress) -> CellAddress? {
        if affectsRows {
            return map(address.row).map { CellAddress(row: $0, column: address.column) }
        }
        return map(address.column).map { CellAddress(row: address.row, column: $0) }
    }

    func adjust(_ reference: A1Reference) -> A1Reference? {
        guard let moved = adjust(reference.address) else { return nil }
        var result = reference
        result.address = moved
        return result
    }

    /// Adjusts the two ends of a range reference such as `A1:B5` or `C:D`.
    func adjustRange(_ startWord: String, _ endWord: String) -> (start: String, end: String)? {
        if var start = A1Reference.parse(startWord), var end = A1Reference.parse(endWord) {
            let along = affectsRows ? (start.address.row, end.address.row) : (start.address.column, end.address.column)
            guard let span = mapSpan(min(along.0, along.1), max(along.0, along.1)) else { return nil }
            if affectsRows {
                start.address.row = span.start
                end.address.row = span.end
            } else {
                start.address.column = span.start
                end.address.column = span.end
            }
            return (start.formatted(), end.formatted())
        }
        if !affectsRows, let start = A1Reference.parseColumn(startWord), let end = A1Reference.parseColumn(endWord) {
            guard let span = mapSpan(min(start.column, end.column), max(start.column, end.column)) else { return nil }
            return ((start.absolute ? "$" : "") + CellAddress.columnName(span.start),
                    (end.absolute ? "$" : "") + CellAddress.columnName(span.end))
        }
        return (startWord, endWord)
    }
}

extension Workbook {
    /// Inserts or deletes rows or columns and updates every formula that refers to them.
    public mutating func apply(_ change: StructuralChange, toSheet index: Int) {
        guard sheets.indices.contains(index) else { return }
        let target = sheets[index].name
        sheets[index].apply(change)
        for s in sheets.indices {
            let formulaSheet = sheets[s].name
            for (address, raw) in sheets[s].cells where CellInput.isFormula(raw) {
                let adjusted = FormulaText.adjusted(raw, for: change, targetSheet: target, formulaSheet: formulaSheet)
                if adjusted != raw { sheets[s].cells[address] = adjusted }
            }
        }
    }

    /// Sorts the rows of a range by one column. Formulas move with their rows, as in Excel.
    /// Empty keys sort last in both directions.
    public mutating func sort(sheet index: Int, range: CellRange, byColumn column: Int, ascending: Bool, hasHeader: Bool) {
        let first = range.start.row + (hasHeader ? 1 : 0)
        guard sheets.indices.contains(index), first < range.end.row else { return }
        let calculator = Calculator(workbook: self)
        let rows = Array(first...range.end.row)
        let keys = rows.map { calculator.value(sheet: index, at: CellAddress(row: $0, column: column)) }
        let order = rows.indices.sorted { a, b in
            switch (keys[a] == .empty, keys[b] == .empty) {
            case (true, true): return a < b
            case (true, false): return false
            case (false, true): return true
            case (false, false):
                let comparison = Calculator.compare(keys[a], keys[b])
                if comparison == 0 { return a < b }
                return ascending ? comparison < 0 : comparison > 0
            }
        }
        rearrange(sheet: index, columns: range.start.column...range.end.column, firstRow: first,
                  sourceRows: order.map { rows[$0] }, clearThrough: range.end.row)
    }

    /// Deletes rows of a range whose shown values repeat an earlier row; returns how many were removed.
    @discardableResult
    public mutating func removeDuplicates(sheet index: Int, range: CellRange, hasHeader: Bool) -> Int {
        let first = range.start.row + (hasHeader ? 1 : 0)
        guard sheets.indices.contains(index), first <= range.end.row else { return 0 }
        let calculator = Calculator(workbook: self)
        var seen = Set<[String]>()
        var keep: [Int] = []
        for row in first...range.end.row {
            let key = (range.start.column...range.end.column).map {
                calculator.displayText(sheet: index, at: CellAddress(row: row, column: $0)).lowercased()
            }
            if seen.insert(key).inserted { keep.append(row) }
        }
        let removed = range.end.row - first + 1 - keep.count
        if removed > 0 {
            rearrange(sheet: index, columns: range.start.column...range.end.column, firstRow: first,
                      sourceRows: keep, clearThrough: range.end.row)
        }
        return removed
    }

    /// Writes `sourceRows` (old row numbers, in their new order) from `firstRow` down, then clears the rest.
    private mutating func rearrange(sheet index: Int, columns: ClosedRange<Int>, firstRow: Int, sourceRows: [Int], clearThrough lastRow: Int) {
        let old = sheets[index]
        var sheet = old
        for row in firstRow...lastRow {
            for column in columns {
                let address = CellAddress(row: row, column: column)
                sheet.cells.removeValue(forKey: address)
                sheet.formats.removeValue(forKey: address)
                sheet.controls.removeValue(forKey: address)
            }
        }
        for (offset, sourceRow) in sourceRows.enumerated() {
            let row = firstRow + offset
            for column in columns {
                let from = CellAddress(row: sourceRow, column: column)
                let to = CellAddress(row: row, column: column)
                if let raw = old.cells[from] {
                    sheet.cells[to] = CellInput.isFormula(raw) ? FormulaText.shifted(raw, rows: row - sourceRow, columns: 0) : raw
                }
                if let format = old.formats[from] { sheet.formats[to] = format }
                if let control = old.controls[from] { sheet.controls[to] = control }
            }
        }
        sheets[index] = sheet
    }

    /// Replaces text in the typed contents (including formulas) of the given cells; returns the count changed.
    @discardableResult
    public mutating func replace(_ query: String, with replacement: String, sheet index: Int, cells addresses: [CellAddress], matchCase: Bool) -> Int {
        guard !query.isEmpty, sheets.indices.contains(index) else { return 0 }
        let options: String.CompareOptions = matchCase ? [] : [.caseInsensitive]
        var count = 0
        for address in addresses {
            guard let raw = sheets[index].cells[address], raw.range(of: query, options: options) != nil else { continue }
            sheets[index].cells[address] = raw.replacingOccurrences(of: query, with: replacement, options: options)
            count += 1
        }
        return count
    }
}

extension Sheet {
    mutating func apply(_ change: StructuralChange) {
        cells = Dictionary(uniqueKeysWithValues: cells.compactMap { address, raw in
            change.adjust(address).map { ($0, raw) }
        })
        formats = Dictionary(uniqueKeysWithValues: formats.compactMap { address, format in
            change.adjust(address).map { ($0, format) }
        })
        controls = Dictionary(uniqueKeysWithValues: controls.compactMap { address, control in
            change.adjust(address).map { ($0, control) }
        })
        canvas = canvas.map { change.adjust($0) }
        if change.affectsRows {
            hiddenRows = Set(hiddenRows.compactMap(change.map))
        } else {
            columnWidths = Dictionary(uniqueKeysWithValues: columnWidths.compactMap { column, width in
                change.map(column).map { ($0, width) }
            })
        }
        if var current = filter {
            let range = current.range
            if change.affectsRows {
                if let header = change.map(range.start.row),
                   let span = change.mapSpan(range.start.row, range.end.row) {
                    current.range = CellRange(CellAddress(row: header, column: range.start.column),
                                              CellAddress(row: span.end, column: range.end.column))
                    filter = current
                } else {
                    filter = nil
                }
            } else if let span = change.mapSpan(range.start.column, range.end.column) {
                current.range = CellRange(CellAddress(row: range.start.row, column: span.start),
                                          CellAddress(row: range.end.row, column: span.end))
                current.allowedValues = Dictionary(uniqueKeysWithValues: current.allowedValues.compactMap { column, values in
                    change.map(column).map { ($0, values) }
                })
                filter = current
            } else {
                filter = nil
            }
        }
        if change.affectsRows {
            rowHeights = Dictionary(uniqueKeysWithValues: rowHeights.compactMap { row, height in
                change.map(row).map { ($0, height) }
            })
        } else {
            hiddenColumns = Set(hiddenColumns.compactMap(change.map))
        }
        merges = merges.compactMap { change.adjust($0) }.filter { $0.cellCount > 1 }
        conditionalFormats = conditionalFormats.compactMap { format in
            var adjusted = format
            adjusted.ranges = format.ranges.compactMap { change.adjust($0) }
            return adjusted.ranges.isEmpty ? nil : adjusted
        }
    }
}

extension StructuralChange {
    /// A range after the change; deleting all of it returns nil.
    func adjust(_ range: CellRange) -> CellRange? {
        if affectsRows {
            guard let span = mapSpan(range.start.row, range.end.row) else { return nil }
            return CellRange(CellAddress(row: span.start, column: range.start.column), CellAddress(row: span.end, column: range.end.column))
        }
        guard let span = mapSpan(range.start.column, range.end.column) else { return nil }
        return CellRange(CellAddress(row: range.start.row, column: span.start), CellAddress(row: range.end.row, column: span.end))
    }
}
