import Foundation

extension Workbook {
    /// Adds a sheet that groups a table's rows by one column, with the count of each group and the total and
    /// average of every numeric column, like a Numbers Smart Categories summary. The summary uses COUNTIFS,
    /// SUMIFS and AVERAGEIFS on the source rows, so it stays up to date as values change.
    /// Returns the new sheet's index, or nil when the table has no data rows.
    @discardableResult
    public mutating func addCategorySummary(sheet index: Int, table: CellRange, hasHeader: Bool, groupBy column: Int) -> Int? {
        guard sheets.indices.contains(index), (table.start.column...table.end.column).contains(column) else { return nil }
        let firstRow = table.start.row + (hasHeader ? 1 : 0)
        guard firstRow <= table.end.row else { return nil }
        let calculator = Calculator(workbook: self)
        let source = sheets[index]
        func value(_ row: Int, _ column: Int) -> CellValue { calculator.value(sheet: index, at: CellAddress(row: row, column: column)) }
        func title(_ column: Int) -> String {
            hasHeader ? calculator.displayText(sheet: index, at: CellAddress(row: table.start.row, column: column))
                : "Column " + CellAddress.columnName(column)
        }

        var groups: [(key: String, value: CellValue)] = []
        var seen = Set<String>()
        for row in firstRow...table.end.row {
            let group = value(row, column)
            guard group != .empty, seen.insert(group.displayText.lowercased()).inserted else { continue }
            groups.append((group.displayText, group))
        }
        groups.sort { Calculator.compareForSort($0.value, $1.value) }

        // Columns where most data cells are numbers are summarised.
        let numeric = (table.start.column...table.end.column).filter { candidate in
            guard candidate != column else { return false }
            let values = (firstRow...table.end.row).map { value($0, candidate) }.filter { $0 != .empty }
            return !values.isEmpty && values.filter(\.isNumber).count * 2 > values.count
        }

        let quoted = "'" + source.name.replacingOccurrences(of: "'", with: "''") + "'!"
        func columnRange(_ c: Int) -> String {
            let letters = CellAddress.columnName(c)
            return "\(quoted)$\(letters)$\(firstRow + 1):$\(letters)$\(table.end.row + 1)"
        }

        var summary = Sheet(name: uniqueSheetName(Workbook.sanitizedSheetName("\(title(column)) Summary")))
        let headerFill = RGBColor(hex: "4472C4")
        let white = RGBColor(hex: "FFFFFF")
        summary.cells[CellAddress(row: 0, column: 0)] = "Summary by \(title(column))"
        summary.setFormat(CellFormat(fontSize: 14, bold: true, textColor: RGBColor(hex: "44546A")), at: CellAddress(row: 0, column: 0))
        summary.cells[CellAddress(row: 1, column: 0)] = "From \(source.name)!\(table.a1). Values update when the data changes."
        summary.setFormat(CellFormat(italic: true, textColor: RGBColor(hex: "7F7F7F")), at: CellAddress(row: 1, column: 0))

        var headers = [title(column), "Count"]
        for c in numeric { headers += ["Total \(title(c))", "Average \(title(c))"] }
        for (offset, text) in headers.enumerated() {
            let address = CellAddress(row: 3, column: offset)
            summary.cells[address] = CellInput.rawInput(for: .text(text))
            summary.setFormat(CellFormat(bold: true, textColor: white, fillColor: headerFill,
                                         alignment: offset == 0 ? .general : .right), at: address)
        }

        let groupRange = columnRange(column)
        let thin = BorderLine(.thin, color: RGBColor(hex: "BFBFBF"))
        for (offset, group) in groups.enumerated() {
            let row = 4 + offset
            let key = "$A\(row + 1)"
            summary.cells[CellAddress(row: row, column: 0)] = CellInput.rawInput(for: group.value)
            summary.cells[CellAddress(row: row, column: 1)] = "=COUNTIFS(\(groupRange),\(key))"
            for (n, c) in numeric.enumerated() {
                let values = columnRange(c)
                summary.cells[CellAddress(row: row, column: 2 + n * 2)] = "=SUMIFS(\(values),\(groupRange),\(key))"
                summary.cells[CellAddress(row: row, column: 3 + n * 2)] = "=IFERROR(AVERAGEIFS(\(values),\(groupRange),\(key)),0)"
                let numberFormat = source.formats[CellAddress(row: firstRow, column: c)]?.numberFormat ?? "#,##0.00"
                let code = numberFormat == "General" ? "#,##0.00" : numberFormat
                summary.setFormat(CellFormat(border: CellBorder(bottom: thin), numberFormat: code), at: CellAddress(row: row, column: 2 + n * 2))
                summary.setFormat(CellFormat(border: CellBorder(bottom: thin), numberFormat: code), at: CellAddress(row: row, column: 3 + n * 2))
            }
            summary.setFormat(CellFormat(border: CellBorder(bottom: thin)), at: CellAddress(row: row, column: 0))
            summary.setFormat(CellFormat(border: CellBorder(bottom: thin)), at: CellAddress(row: row, column: 1))
        }

        let totalRow = 4 + groups.count
        summary.cells[CellAddress(row: totalRow, column: 0)] = "Total"
        for offset in 1..<headers.count where offset == 1 || offset % 2 == 0 {
            let letters = CellAddress.columnName(offset)
            summary.cells[CellAddress(row: totalRow, column: offset)] = groups.isEmpty ? "0" : "=SUM(\(letters)5:\(letters)\(totalRow))"
        }
        for offset in 0..<headers.count {
            let address = CellAddress(row: totalRow, column: offset)
            var format = summary.formats[CellAddress(row: totalRow - 1, column: offset)] ?? CellFormat()
            format.bold = true
            format.border = CellBorder(top: BorderLine(.thin, color: headerFill), bottom: BorderLine(.double, color: headerFill))
            summary.setFormat(format, at: address)
        }
        summary.columnWidths[0] = 140
        for offset in 1..<headers.count { summary.columnWidths[offset] = 110 }
        summary.frozenRows = 4
        sheets.append(summary)
        return sheets.count - 1
    }

    /// A sheet name not used yet: the name itself, or the name followed by 2, 3, …
    func uniqueSheetName(_ base: String) -> String {
        let root = base.isEmpty ? "Sheet" : base
        guard sheetIndex(named: root) != nil else { return root }
        var number = 2
        while sheetIndex(named: Workbook.sanitizedSheetName("\(root.prefix(27)) \(number)")) != nil { number += 1 }
        return Workbook.sanitizedSheetName("\(root.prefix(27)) \(number)")
    }
}
