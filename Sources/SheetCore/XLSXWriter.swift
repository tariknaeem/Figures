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
        xml += controlsXML(sheet.controls, canvas: sheet.canvas)
        return xml + "</worksheet>"
    }

    /// Identifies Figures' own worksheet extension; Excel skips extensions it does not know.
    static let controlsExtension = "{3F1D8C2A-6B4E-4E8F-9A7C-2D5B1E0F4A6C}"
    static let controlsNamespace = "https://github.com/tariknaeem/Figures/controls"

    /// Pop-up menus with a short list or a range become Excel data validation lists; the other controls,
    /// and lists Excel cannot hold inline, go in a Figures extension.
    private static func controlsXML(_ controls: [CellAddress: CellControl], canvas: [CanvasObject]) -> String {
        guard !controls.isEmpty || !canvas.isEmpty else { return "" }
        var validations: [(sqref: String, formula: String)] = []
        var extensions: [(sqref: String, control: CellControl)] = []
        for (control, addresses) in Dictionary(grouping: controls.keys, by: { controls[$0]! }).sorted(by: { $0.value.min()! < $1.value.min()! }) {
            let sqref = compressed(addresses)
            if case .popUp(let source) = control {
                switch source {
                case .range(let reference):
                    validations.append((sqref, reference))
                    continue
                case .items(let items):
                    let inline = "\"" + items.joined(separator: ",") + "\""
                    if inline.count <= 255, !items.contains(where: { $0.contains(",") || $0.contains("\"") }) {
                        validations.append((sqref, inline))
                        continue
                    }
                }
            }
            extensions.append((sqref, control))
        }
        var xml = ""
        if !validations.isEmpty {
            xml += #"<dataValidations count="\#(validations.count)">"#
            for validation in validations {
                xml += #"<dataValidation type="list" allowBlank="1" showErrorMessage="1" sqref="\#(validation.sqref)"><formula1>\#(XML.escape(validation.formula))</formula1></dataValidation>"#
            }
            xml += "</dataValidations>"
        }
        if !extensions.isEmpty || !canvas.isEmpty {
            xml += #"<extLst><ext uri="\#(controlsExtension)" xmlns:fig="\#(controlsNamespace)"><fig:controls>"#
            for item in extensions {
                switch item.control {
                case .checkbox: xml += #"<fig:control sqref="\#(item.sqref)" type="checkbox"/>"#
                case .rating: xml += #"<fig:control sqref="\#(item.sqref)" type="rating"/>"#
                case .stepper(let low, let high, let step), .slider(let low, let high, let step):
                    let type = if case .stepper = item.control { "stepper" } else { "slider" }
                    xml += #"<fig:control sqref="\#(item.sqref)" type="\#(type)" min="\#(NumberText.roundTrip(low))" max="\#(NumberText.roundTrip(high))" step="\#(NumberText.roundTrip(step))"/>"#
                case .popUp(let source):
                    if case .items(let items) = source {
                        xml += #"<fig:control sqref="\#(item.sqref)" type="popup">"#
                        for option in items { xml += "<fig:item>\(XML.escape(option))</fig:item>" }
                        xml += "</fig:control>"
                    }
                }
            }
            xml += "</fig:controls>"
            if !canvas.isEmpty { xml += canvasXML(canvas) }
            xml += "</ext></extLst>"
        }
        return xml
    }

    private static func canvasXML(_ objects: [CanvasObject]) -> String {
        func number(_ value: Double) -> String { NumberText.roundTrip((value * 100).rounded() / 100) }
        var xml = "<fig:canvas>"
        for object in objects {
            var attributes = #" id="\#(object.id.uuidString)" x="\#(number(object.x))" y="\#(number(object.y))""#
            attributes += #" width="\#(number(object.width))" height="\#(number(object.height))""#
            attributes += #" fontSize="\#(number(object.fontSize))""# + (object.bold ? #" bold="1""# : "")
            if let fill = object.fill { attributes += #" fill="\#(fill.hex)""# }
            if let stroke = object.stroke { attributes += #" stroke="\#(stroke.hex)""# }
            if let color = object.textColor { attributes += #" textColor="\#(color.hex)""# }
            switch object.kind {
            case .chart(let kind, let range, let title):
                xml += #"<fig:object type="chart" chart="\#(kind.rawValue)" range="\#(range.a1)" title="\#(XML.escape(title))"\#(attributes)/>"#
            case .text(let text):
                xml += #"<fig:object type="text"\#(attributes)><fig:text>\#(XML.escape(text))</fig:text></fig:object>"#
            case .shape(let shape):
                xml += #"<fig:object type="shape" shape="\#(shape.rawValue)"\#(attributes)/>"#
            case .image(let data):
                xml += #"<fig:object type="image"\#(attributes)><fig:data>\#(data.base64EncodedString())</fig:data></fig:object>"#
            }
        }
        return xml + "</fig:canvas>"
    }

    /// Writes addresses as a space-separated sqref, joining runs down each column into ranges.
    static func compressed(_ addresses: [CellAddress]) -> String {
        let sorted = addresses.sorted { ($0.column, $0.row) < ($1.column, $1.row) }
        var parts: [String] = []
        var index = 0
        while index < sorted.count {
            let start = sorted[index]
            var end = start
            while index + 1 < sorted.count, sorted[index + 1].column == start.column, sorted[index + 1].row == end.row + 1 {
                index += 1
                end = sorted[index]
            }
            parts.append(CellRange(start, end).a1)
            index += 1
        }
        return parts.joined(separator: " ")
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
