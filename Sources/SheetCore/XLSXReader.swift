import Foundation

/// Reads `.xlsx` and `.xlsm` workbooks: values, formulas, styles with theme colors, layout,
/// merges, filters and conditional formatting. Charts, images, comments and macros are not read.
public enum XLSXReader {
    public static func workbook(from data: Data) throws -> Workbook {
        // OLE compound files are Excel 97–2003 workbooks or password-encrypted .xlsx files.
        if data.starts(with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) {
            throw XLSXError.unsupportedContainer
        }
        let archive = try ZipArchive(data: data)

        var workbookPath = "xl/workbook.xml"
        if archive.contains("_rels/.rels") {
            let rels = try relationships(archive, "_rels/.rels", base: "")
            if let main = rels.values.first(where: { $0.type.hasSuffix("/officeDocument") }) { workbookPath = main.target }
        }
        let workbookXML = try XML.parse(archive.data(workbookPath))
        let workbookDirectory = directory(of: workbookPath)
        let relsPath = workbookDirectory + "_rels/" + fileName(of: workbookPath) + ".rels"
        let rels = try relationships(archive, relsPath, base: workbookDirectory)

        func part(_ suffix: String) throws -> XMLNodeTree? {
            guard let rel = rels.values.first(where: { $0.type.hasSuffix(suffix) }), archive.contains(rel.target) else { return nil }
            return try XML.parse(archive.data(rel.target))
        }
        let colors = ColorResolver(themeXML: try part("/theme"))
        let sharedStrings = try part("/sharedStrings")?.children("si").map(richText) ?? []
        let styles = StyleReader(try part("/styles"), colors: colors)

        var sheets: [Sheet] = []
        // localSheetId counts every <sheet> entry, including chart sheets this app skips.
        var sheetIndexForEntry: [Int: Int] = [:]
        for (entryIndex, entry) in (workbookXML.child("sheets")?.children("sheet") ?? []).enumerated() {
            guard let name = entry.attribute("name"), let id = entry.attribute("id"), let rel = rels[id],
                  rel.type.hasSuffix("/worksheet"), archive.contains(rel.target) else { continue }
            sheetIndexForEntry[entryIndex] = sheets.count
            var sheet = Sheet(name: name)
            try readSheet(XML.parse(archive.data(rel.target)), into: &sheet, sharedStrings: sharedStrings, styles: styles, colors: colors)
            sheets.append(sheet)
        }
        guard !sheets.isEmpty else { throw XLSXError.malformed("no worksheets found") }
        var workbook = Workbook(sheets: sheets)
        workbook.definedNames = (workbookXML.child("definedNames")?.children("definedName") ?? []).compactMap { node in
            guard let name = node.attribute("name"), !name.hasPrefix("_xlnm."), !node.text.isEmpty else { return nil }
            let scope = node.attribute("localSheetId").flatMap(Int.init)
            if scope != nil, sheetIndexForEntry[scope!] == nil { return nil }
            return DefinedName(name: name, formula: String(FormulaText.fromFileForm(node.text).dropFirst()), scope: scope.flatMap { sheetIndexForEntry[$0] })
        }
        workbook.defaultFontName = styles.defaultFontName
        workbook.defaultFontSize = styles.defaultFontSize
        return workbook
    }

    private static func readSheet(_ root: XMLNodeTree, into sheet: inout Sheet, sharedStrings: [String],
                                  styles: StyleReader, colors: ColorResolver) throws {
        if let view = root.child("sheetViews")?.child("sheetView") {
            sheet.showGridlines = view.flag("showGridLines", default: true)
            if let pane = view.child("pane"), ["frozen", "frozenSplit"].contains(pane.attribute("state") ?? ""),
               let split = pane.attribute("ySplit").flatMap(Double.init), split >= 1 {
                sheet.frozenRows = min(Int(split), 100)
            }
        }
        if let properties = root.child("sheetFormatPr") {
            if let height = properties.attribute("defaultRowHeight").flatMap(Double.init), height > 0 { sheet.defaultRowHeight = height }
            if let width = properties.attribute("defaultColWidth").flatMap(Double.init), width > 0 {
                sheet.defaultColumnWidth = ColumnWidth.points(excelWidth: width)
            } else if let base = properties.attribute("baseColWidth").flatMap(Double.init), base > 0 {
                sheet.defaultColumnWidth = ColumnWidth.points(excelWidth: base + 0.71)
            }
        }

        for column in root.child("cols")?.children("col") ?? [] {
            guard let min = column.attribute("min").flatMap(Int.init), let max = column.attribute("max").flatMap(Int.init),
                  min >= 1, max >= min, max <= CellAddress.maxColumns else { continue }
            // Whole-sheet column records carry no per-column information worth expanding.
            guard max - min < 1_000 else { continue }
            let width = column.attribute("width").flatMap(Double.init)
            let hidden = column.flag("hidden")
            for index in (min - 1)...(max - 1) {
                if let width, abs(ColumnWidth.points(excelWidth: width) - sheet.defaultColumnWidth) > 0.5 {
                    sheet.columnWidths[index] = ColumnWidth.points(excelWidth: width)
                }
                if hidden || width == 0 { sheet.hiddenColumns.insert(index) }
            }
        }

        let autoFilter = root.child("autoFilter")
        if let ref = autoFilter?.attribute("ref"), let range = RangeList.parse(ref).first {
            var filter = AutoFilter(range: range)
            for column in autoFilter?.children("filterColumn") ?? [] {
                guard let id = column.attribute("colId").flatMap(Int.init), let filters = column.child("filters") else { continue }
                var allowed = Set(filters.children("filter").compactMap { $0.attribute("val") })
                if filters.flag("blank") { allowed.insert("") }
                filter.allowedValues[filter.range.start.column + id] = allowed
            }
            sheet.filter = filter
        }

        sheet.merges = (root.child("mergeCells")?.children("mergeCell") ?? []).compactMap { node in
            node.attribute("ref").flatMap { RangeList.parse($0).first }.flatMap { $0.cellCount > 1 ? $0 : nil }
        }

        let rules = root.children("conditionalFormatting").flatMap { block -> [(Int, ConditionalFormat)] in
            let ranges = RangeList.parse(block.attribute("sqref") ?? "")
            guard !ranges.isEmpty else { return [] }
            return block.children("cfRule").compactMap { node in
                conditionalRule(node, styles: styles, colors: colors).map { rule in
                    (node.attribute("priority").flatMap(Int.init) ?? Int.max,
                     ConditionalFormat(ranges: ranges, rule: rule, stopIfTrue: node.flag("stopIfTrue")))
                }
            }
        }
        sheet.conditionalFormats = rules.enumerated().sorted { a, b in
            a.element.0 != b.element.0 ? a.element.0 < b.element.0 : a.offset < b.offset
        }.map(\.element.1)

        // Shared formulas store their text once, on the first cell of the block.
        var sharedFormulas: [String: (formula: String, origin: CellAddress)] = [:]
        var lastRow = 0
        for row in root.child("sheetData")?.children("row") ?? [] {
            let rowNumber = row.attribute("r").flatMap(Int.init) ?? lastRow + 1
            lastRow = rowNumber
            guard rowNumber >= 1, rowNumber <= CellAddress.maxRows else { continue }
            // Rows the AutoFilter hides are recomputed from its criteria.
            if autoFilter == nil, row.flag("hidden") { sheet.hiddenRows.insert(rowNumber - 1) }
            if let height = row.attribute("ht").flatMap(Double.init), abs(height - sheet.defaultRowHeight) > 0.01 {
                sheet.rowHeights[rowNumber - 1] = height
            }
            var nextColumn = 0
            for cell in row.children("c") {
                let address = cell.attribute("r").flatMap { CellAddress(a1: $0) } ?? CellAddress(row: rowNumber - 1, column: nextColumn)
                nextColumn = address.column + 1
                guard address.isValid else { continue }

                if let style = cell.attribute("s").flatMap(Int.init), let format = styles.format(at: style) {
                    sheet.setFormat(format, at: address)
                }

                var raw: String?
                if let f = cell.child("f") {
                    var formula = f.text
                    if f.attribute("t") == "shared", let id = f.attribute("si") {
                        if !formula.isEmpty {
                            sharedFormulas[id] = (formula, address)
                        } else if let master = sharedFormulas[id] {
                            formula = String(FormulaText.shifted(
                                "=" + master.formula,
                                rows: address.row - master.origin.row,
                                columns: address.column - master.origin.column
                            ).dropFirst())
                        }
                    }
                    if !formula.isEmpty { raw = FormulaText.fromFileForm(formula) }
                }
                if raw == nil {
                    let v = cell.child("v")?.text
                    let value: CellValue
                    switch cell.attribute("t") ?? "n" {
                    case "s": value = v.flatMap(Int.init).flatMap { sharedStrings.indices.contains($0) ? .text(sharedStrings[$0]) : nil } ?? .empty
                    case "inlineStr": value = cell.child("is").map { .text(richText($0)) } ?? .empty
                    case "str", "d": value = v.map { .text($0) } ?? .empty
                    case "b": value = .boolean(v == "1" || v == "true")
                    case "e": value = v.map { .text($0) } ?? .empty
                    default: value = v.flatMap(Double.init).map { .number($0) } ?? .empty
                    }
                    raw = CellInput.rawInput(for: value)
                }
                if let raw, !raw.isEmpty { sheet.cells[address] = raw }
            }
        }
    }

    private static func conditionalRule(_ node: XMLNodeTree, styles: StyleReader, colors: ColorResolver) -> ConditionalRule? {
        let style = node.attribute("dxfId").flatMap(Int.init).flatMap { styles.differentialStyles.indices.contains($0) ? styles.differentialStyles[$0] : nil }
            ?? DifferentialStyle()
        let formulas = node.children("formula").map(\.text)
        switch node.attribute("type") ?? "" {
        case "cellIs":
            guard let op = ComparisonOperator(rawValue: node.attribute("operator") ?? ""), let first = formulas.first else { return nil }
            return .cellIs(op, first, formulas.count > 1 ? formulas[1] : nil, style)
        case "containsText", "notContainsText", "beginsWith", "endsWith":
            guard let match = TextMatch(rawValue: node.attribute("type")!), let text = node.attribute("text") else { return nil }
            return .text(match, text, style)
        case "duplicateValues": return .duplicates(unique: false, style)
        case "uniqueValues": return .duplicates(unique: true, style)
        case "top10":
            return .top(rank: node.attribute("rank").flatMap(Int.init) ?? 10, bottom: node.flag("bottom"), percent: node.flag("percent"), style)
        case "aboveAverage":
            return .average(below: !node.flag("aboveAverage", default: true), style)
        case "expression":
            return formulas.first.map { .expression($0, style) }
        case "colorScale":
            guard let scale = node.child("colorScale") else { return nil }
            let values = scale.children("cfvo")
            let stopColors = scale.children("color").map { colors.resolve($0) ?? RGBColor(red: 255, green: 255, blue: 255) }
            guard values.count == stopColors.count, (2...3).contains(values.count) else { return nil }
            return .colorScale(zip(values, stopColors).map { cfvo, color in
                ScaleStop(ScaleValueKind(rawValue: cfvo.attribute("type") ?? "") ?? .min, cfvo.attribute("val"), color: color)
            })
        case "dataBar":
            let color = colors.resolve(node.child("dataBar")?.child("color")) ?? RGBColor(red: 0x63, green: 0x8E, blue: 0xC6)
            return .dataBar(color)
        default:
            // Icon sets, time periods and blank tests are not supported.
            return nil
        }
    }

    /// Text of an `<si>` or `<is>` element: plain or rich-text runs, without phonetic hints,
    /// cut to Excel's 32,767-character cell limit.
    private static func richText(_ node: XMLNodeTree) -> String {
        let text = node.child("t")?.text ?? node.children("r").compactMap { $0.child("t")?.text }.joined()
        return text.utf8.count > 32_767 ? String(text.prefix(32_767)) : text
    }

    private struct Relationship {
        let type: String
        let target: String
    }

    private static func relationships(_ archive: ZipArchive, _ path: String, base: String) throws -> [String: Relationship] {
        guard archive.contains(path) else { return [:] }
        var result: [String: Relationship] = [:]
        for rel in try XML.parse(archive.data(path)).children("Relationship") {
            guard let id = rel.attribute("Id"), let target = rel.attribute("Target"), rel.attribute("TargetMode") != "External" else { continue }
            result[id] = Relationship(type: rel.attribute("Type") ?? "", target: resolve(target, base: base))
        }
        return result
    }

    private static func resolve(_ target: String, base: String) -> String {
        let target = target.replacingOccurrences(of: "\\", with: "/")
        let joined = target.hasPrefix("/") ? String(target.dropFirst()) : base + target
        var parts: [Substring] = []
        for part in joined.split(separator: "/") {
            if part == ".." { _ = parts.popLast() } else if part != "." { parts.append(part) }
        }
        return parts.joined(separator: "/")
    }

    private static func directory(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[...slash])
    }

    private static func fileName(of path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}
