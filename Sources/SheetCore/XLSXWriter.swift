import Foundation

public enum XLSXWriter {
    private static let main = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    private static let relationships = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    private static let packageRelationships = "http://schemas.openxmlformats.org/package/2006/relationships"
    static let header = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"# + "\n"

    /// An Office Open XML workbook. Formulas carry cached values so other apps can show them before recalculating.
    public static func data(for workbook: Workbook) -> Data {
        let calculator = Calculator(workbook: workbook)
        var styles = StyleTable(defaultFontName: workbook.defaultFontName, defaultFontSize: workbook.defaultFontSize)
        var zip = ZipWriter()
        let sheetCount = workbook.sheets.count

        var contentTypes = header + #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">"#
        contentTypes += #"<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>"#
        contentTypes += #"<Default Extension="xml" ContentType="application/xml"/>"#
        contentTypes += #"<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>"#
        for i in 1...sheetCount {
            contentTypes += #"<Override PartName="/xl/worksheets/sheet\#(i).xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>"#
        }
        contentTypes += #"<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>"#
        contentTypes += "</Types>"
        zip.add("[Content_Types].xml", contentTypes)

        zip.add("_rels/.rels", header + #"<Relationships xmlns="\#(packageRelationships)"><Relationship Id="rId1" Type="\#(relationships)/officeDocument" Target="xl/workbook.xml"/></Relationships>"#)

        var workbookXML = header + #"<workbook xmlns="\#(main)" xmlns:r="\#(relationships)"><sheets>"#
        var workbookRels = header + #"<Relationships xmlns="\#(packageRelationships)">"#
        var definedNames = ""
        for (i, sheet) in workbook.sheets.enumerated() {
            workbookXML += #"<sheet name="\#(XML.escape(sheet.name))" sheetId="\#(i + 1)" r:id="rId\#(i + 1)"/>"#
            workbookRels += #"<Relationship Id="rId\#(i + 1)" Type="\#(relationships)/worksheet" Target="worksheets/sheet\#(i + 1).xml"/>"#
            if let filter = sheet.filter {
                // Excel records each sheet's AutoFilter range under this hidden name.
                let quoted = "'" + sheet.name.replacingOccurrences(of: "'", with: "''") + "'!" + absolute(filter.range)
                definedNames += #"<definedName name="_xlnm._FilterDatabase" localSheetId="\#(i)" hidden="1">\#(XML.escape(quoted))</definedName>"#
            }
        }
        for name in workbook.definedNames {
            let scope = name.scope.map { #" localSheetId="\#($0)""# } ?? ""
            definedNames += #"<definedName name="\#(XML.escape(name.name))"\#(scope)>\#(XML.escape(FormulaText.fileForm("=" + name.formula)))</definedName>"#
        }
        workbookXML += "</sheets>"
        if !definedNames.isEmpty { workbookXML += "<definedNames>\(definedNames)</definedNames>" }
        workbookXML += #"<calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>"#
        workbookRels += #"<Relationship Id="rId\#(sheetCount + 1)" Type="\#(relationships)/styles" Target="styles.xml"/></Relationships>"#
        zip.add("xl/workbook.xml", workbookXML)
        zip.add("xl/_rels/workbook.xml.rels", workbookRels)

        for (i, sheet) in workbook.sheets.enumerated() {
            zip.add("xl/worksheets/sheet\(i + 1).xml", sheetXML(sheet, index: i, calculator: calculator, styles: &styles))
        }
        zip.add("xl/styles.xml", styles.xml)
        return zip.finish()
    }

    private static func absolute(_ range: CellRange) -> String {
        func cell(_ a: CellAddress) -> String { "$" + CellAddress.columnName(a.column) + "$" + String(a.row + 1) }
        return cell(range.start) + ":" + cell(range.end)
    }

    // Element order follows the worksheet schema: sheetViews, sheetFormatPr, cols, sheetData,
    // autoFilter, mergeCells, conditionalFormatting.
    private static func sheetXML(_ sheet: Sheet, index: Int, calculator: Calculator, styles: inout StyleTable) -> String {
        var xml = header + #"<worksheet xmlns="\#(main)">"#
        if sheet.frozenRows > 0 || !sheet.showGridlines {
            xml += #"<sheetViews><sheetView workbookViewId="0""# + (sheet.showGridlines ? "" : #" showGridLines="0""#) + ">"
            if sheet.frozenRows > 0 {
                xml += #"<pane ySplit="\#(sheet.frozenRows)" topLeftCell="A\#(sheet.frozenRows + 1)" activePane="bottomLeft" state="frozen"/>"#
            }
            xml += "</sheetView></sheetViews>"
        }
        xml += #"<sheetFormatPr defaultRowHeight="\#(NumberText.roundTrip(sheet.defaultRowHeight))""#
        if abs(sheet.defaultColumnWidth - 64) > 0.01 {
            xml += #" defaultColWidth="\#(ColumnWidth.excelWidth(points: sheet.defaultColumnWidth))""#
        }
        xml += "/>"

        let columns = Set(sheet.columnWidths.keys).union(sheet.hiddenColumns).sorted()
        if !columns.isEmpty {
            xml += "<cols>"
            for column in columns {
                let width = sheet.columnWidths[column] ?? sheet.defaultColumnWidth
                xml += #"<col min="\#(column + 1)" max="\#(column + 1)" width="\#(ColumnWidth.excelWidth(points: width))""#
                if sheet.columnWidths[column] != nil { xml += #" customWidth="1""# }
                if sheet.hiddenColumns.contains(column) { xml += #" hidden="1""# }
                xml += "/>"
            }
            xml += "</cols>"
        }

        xml += "<sheetData>"
        let hidden = calculator.hiddenRows(sheet: index)
        let byRow = Dictionary(grouping: Set(sheet.cells.keys).union(sheet.formats.keys), by: \.row)
        for row in Set(byRow.keys).union(hidden).union(sheet.rowHeights.keys).sorted() {
            xml += #"<row r="\#(row + 1)""#
            if let height = sheet.rowHeights[row] { xml += #" ht="\#(NumberText.roundTrip(height))" customHeight="1""# }
            if hidden.contains(row) { xml += #" hidden="1""# }
            xml += ">"
            for address in (byRow[row] ?? []).sorted() {
                xml += cellXML(address, sheet: sheet, index: index, calculator: calculator, styles: &styles)
            }
            xml += "</row>"
        }
        xml += "</sheetData>"

        if let filter = sheet.filter {
            xml += #"<autoFilter ref="\#(filter.range.a1)">"#
            for (column, allowed) in filter.allowedValues.sorted(by: { $0.key < $1.key }) {
                xml += #"<filterColumn colId="\#(column - filter.range.start.column)"><filters"#
                xml += (allowed.contains("") ? #" blank="1""# : "") + ">"
                for value in allowed.sorted() where !value.isEmpty {
                    xml += #"<filter val="\#(XML.escape(value))"/>"#
                }
                xml += "</filters></filterColumn>"
            }
            xml += "</autoFilter>"
        }
        if !sheet.merges.isEmpty {
            xml += #"<mergeCells count="\#(sheet.merges.count)">"#
            for merge in sheet.merges { xml += #"<mergeCell ref="\#(merge.a1)"/>"# }
            xml += "</mergeCells>"
        }
        for (priority, format) in sheet.conditionalFormats.enumerated() {
            xml += conditionalXML(format, priority: priority + 1, styles: &styles)
        }
        return xml + "</worksheet>"
    }

    private static func conditionalXML(_ format: ConditionalFormat, priority: Int, styles: inout StyleTable) -> String {
        let sqref = format.ranges.map(\.a1).joined(separator: " ")
        var rule = #"<cfRule priority="\#(priority)""# + (format.stopIfTrue ? #" stopIfTrue="1""# : "")
        if let style = format.rule.style { rule += #" dxfId="\#(styles.dxfIndex(for: style))""# }
        func formula(_ text: String) -> String { "<formula>\(XML.escape(text))</formula>" }
        let origin = format.origin.a1

        switch format.rule {
        case .cellIs(let op, let first, let second, _):
            rule += #" type="cellIs" operator="\#(op.rawValue)">"# + formula(first) + (second.map(formula) ?? "")
        case .text(let match, let text, _):
            let quoted = "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            let (op, test): (String, String) = switch match {
            case .containsText: ("containsText", "NOT(ISERROR(SEARCH(\(quoted),\(origin))))")
            case .notContainsText: ("notContains", "ISERROR(SEARCH(\(quoted),\(origin)))")
            case .beginsWith: ("beginsWith", "LEFT(\(origin),LEN(\(quoted)))=\(quoted)")
            case .endsWith: ("endsWith", "RIGHT(\(origin),LEN(\(quoted)))=\(quoted)")
            }
            rule += #" type="\#(match.rawValue)" operator="\#(op)" text="\#(XML.escape(text))">"# + formula(test)
        case .duplicates(let unique, _):
            rule += #" type="\#(unique ? "uniqueValues" : "duplicateValues")">"#
        case .top(let rank, let bottom, let percent, _):
            rule += #" type="top10" rank="\#(rank)""# + (bottom ? #" bottom="1""# : "") + (percent ? #" percent="1""# : "") + ">"
        case .average(let below, _):
            rule += #" type="aboveAverage""# + (below ? #" aboveAverage="0""# : "") + ">"
        case .expression(let text, _):
            rule += #" type="expression">"# + formula(text)
        case .colorScale(let stops):
            rule += #" type="colorScale"><colorScale>"#
            for stop in stops {
                rule += #"<cfvo type="\#(stop.kind.rawValue)""# + (stop.value.map { #" val="\#(XML.escape($0))""# } ?? "") + "/>"
            }
            for stop in stops { rule += #"<color rgb="FF\#(stop.color.hex)"/>"# }
            rule += "</colorScale>"
        case .dataBar(let color):
            rule += #" type="dataBar"><dataBar><cfvo type="min"/><cfvo type="max"/><color rgb="FF\#(color.hex)"/></dataBar>"#
        }
        return #"<conditionalFormatting sqref="\#(sqref)">\#(rule)</cfRule></conditionalFormatting>"#
    }

    private static func cellXML(_ address: CellAddress, sheet: Sheet, index: Int, calculator: Calculator, styles: inout StyleTable) -> String {
        var attributes = #" r="\#(address.a1)""#
        if let format = sheet.formats[address] {
            let style = styles.index(for: format)
            if style != 0 { attributes += #" s="\#(style)""# }
        }
        guard let raw = sheet.cells[address] else { return "<c\(attributes)/>" }

        if CellInput.isFormula(raw) {
            let formula = "<f>\(XML.escape(FormulaText.fileForm(raw)))</f>"
            switch calculator.value(sheet: index, at: address) {
            case .number(let n): return "<c\(attributes)>\(formula)<v>\(NumberText.roundTrip(n))</v></c>"
            case .text(let s): return #"<c\#(attributes) t="str">\#(formula)<v>\#(XML.escape(s))</v></c>"#
            case .boolean(let b): return #"<c\#(attributes) t="b">\#(formula)<v>\#(b ? 1 : 0)</v></c>"#
            case .error(.circular), .empty: return "<c\(attributes)>\(formula)</c>"
            case .error(let e): return #"<c\#(attributes) t="e">\#(formula)<v>\#(XML.escape(e.rawValue))</v></c>"#
            }
        }
        switch CellInput.literalValue(raw) {
        case .number(let n): return "<c\(attributes)><v>\(NumberText.roundTrip(n))</v></c>"
        case .boolean(let b): return #"<c\#(attributes) t="b"><v>\#(b ? 1 : 0)</v></c>"#
        case .text(let s): return #"<c\#(attributes) t="inlineStr"><is><t xml:space="preserve">\#(XML.escape(s))</t></is></c>"#
        case .empty, .error: return "<c\(attributes)/>"
        }
    }
}
