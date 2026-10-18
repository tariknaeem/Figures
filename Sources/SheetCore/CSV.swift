import Foundation

/// RFC 4180 delimited text, also used for tab-separated clipboard contents.
public enum CSV {
    public static func rows(_ text: String, delimiter: Character = ",") -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else if c == "\"" && field.isEmpty {
                inQuotes = true
            } else if c == delimiter {
                row.append(field)
                field = ""
            } else if c.isNewline {
                // Swift treats "\r\n" as one Character.
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(c)
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    public static func encode(_ rows: [[String]], delimiter: Character = ",") -> String {
        rows.map { row in
            row.map { field in
                let needsQuotes = field.contains(delimiter) || field.contains("\"") || field.contains(where: \.isNewline)
                    || field.first == " " || field.last == " "
                return needsQuotes ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : field
            }.joined(separator: String(delimiter))
        }.joined(separator: "\r\n")
    }

    /// Imports text the way Excel opens a CSV: each field is treated as typed input.
    public static func sheet(from text: String, named name: String) -> Sheet {
        var sheet = Sheet(name: name)
        for (r, row) in rows(text).enumerated() where r < CellAddress.maxRows {
            for (c, field) in row.enumerated() where c < CellAddress.maxColumns && !field.isEmpty {
                sheet.cells[CellAddress(row: r, column: c)] = field
            }
        }
        return sheet
    }

    /// Exports one sheet's displayed values.
    public static func data(for workbook: Workbook, sheet index: Int) -> Data {
        guard workbook.sheets.indices.contains(index) else { return Data() }
        let sheet = workbook.sheets[index]
        guard let maxRow = sheet.maxRow, let maxColumn = sheet.maxColumn else { return Data() }
        let calculator = Calculator(workbook: workbook)
        let rows = (0...maxRow).map { row in
            (0...maxColumn).map { calculator.displayText(sheet: index, at: CellAddress(row: row, column: $0)) }
        }
        return Data((encode(rows) + "\r\n").utf8)
    }
}
