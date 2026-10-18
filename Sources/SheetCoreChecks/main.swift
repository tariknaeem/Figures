import Foundation
import SheetCore

// Engine checks. Run with `swift run SheetCoreChecks`; exits non-zero on failure.
// With file arguments, reports how each workbook was read instead: `swift run SheetCoreChecks a.xlsx`.
// `swift run SheetCoreChecks --tour Tour.xlsx` writes a workbook that shows off the formatting features,
// and `--templates Templates.xlsx` one with every template.
// `swift run -c release SheetCoreChecks --bench` times calculation on a large workbook.

if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--bench" {
    func seconds(_ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
    }
    func ms(_ s: Double) -> String { String(format: "%8.1f ms", s * 1000) }

    let rows = 5_000
    var sheet = Sheet(name: "Data")
    for r in 1...rows {
        sheet.cells[CellAddress(row: r - 1, column: 0)] = String(r)
        sheet.cells[CellAddress(row: r - 1, column: 1)] = "=A\(r)*2"
        sheet.cells[CellAddress(row: r - 1, column: 2)] = r == 1 ? "=B1" : "=C\(r - 1)+B\(r)"
        sheet.cells[CellAddress(row: r - 1, column: 3)] = "=IF(MOD(A\(r),3)=0,\"fizz\",A\(r))"
        if r <= 200 {
            sheet.cells[CellAddress(row: r - 1, column: 4)] = "=VLOOKUP(\(r * 7),A:B,2,FALSE)"
            sheet.cells[CellAddress(row: r - 1, column: 5)] = "=SUM(B:B)/COUNT(A:A)"
        }
    }
    var workbook = Workbook(sheets: [sheet])
    let all = Array(workbook.sheets[0].cells.keys).sorted()
    let viewport = (0..<45).flatMap { r in (0..<12).map { CellAddress(row: r, column: $0) } }
    print("Workbook: \(all.count) cells, \(all.filter { workbook.sheets[0].cells[$0]!.hasPrefix("=") }.count) formulas")

    var calculator = Calculator(workbook: workbook)
    print("Cold: calculate every cell        ", ms(seconds { for a in all { _ = calculator.value(sheet: 0, at: a) } }))
    print("Cold: one screen of display text   ", ms(seconds { for a in viewport { _ = calculator.displayText(sheet: 0, at: a) } }))

    // An edit near the top, as when typing into a cell.
    var edits: [Double] = []
    for (i, address) in [CellAddress(row: 9, column: 0), CellAddress(row: 3_000, column: 0), CellAddress(row: 20, column: 6)].enumerated() {
        let previous = calculator
        workbook.sheets[0].cells[address] = String(1_000 + i)
        edits.append(seconds {
            calculator = Calculator.updating(previous, for: workbook)
            for a in viewport { _ = calculator.displayText(sheet: 0, at: a) }
        })
    }
    print("After an edit: refresh one screen  ", edits.map(ms).joined(separator: " "))
    let fresh = Calculator(workbook: workbook)
    print("Values match a full recalculation: ",
          all.allSatisfy { calculator.value(sheet: 0, at: $0) == fresh.value(sheet: 0, at: $0) } ? "yes" : "NO")
    exit(0)
}

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--templates" {
    var book = Workbook(sheets: [])
    for template in SheetTemplate.allCases { book.addSheet(from: template) }
    book.sheets.removeAll { $0.name == "Sheet1" }
    do {
        try XLSXWriter.data(for: book).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
        print("Wrote \(CommandLine.arguments[2])")
        exit(0)
    } catch {
        print("Could not write the templates: \(error.localizedDescription)")
        exit(1)
    }
}

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--tour" {
    func at(_ a1: String) -> CellAddress { CellAddress(a1: a1)! }
    func hex(_ value: String) -> RGBColor { RGBColor(hex: value)! }
    var budget = Sheet(name: "Budget")
    let rows: [(String, String, Double, Double, String)] = [
        ("Rent", "Home", 1800, 1800, "Due on the 1st"),
        ("Groceries", "Food", 650, 712.4, "Includes the weekly farmers market and one big monthly shop"),
        ("Utilities", "Home", 220, 198.75, ""),
        ("Transport", "Travel", 300, 341.2, "Fuel went up in March"),
        ("Dining out", "Food", 250, 305.6, ""),
        ("Insurance", "Home", 180, 180, "Annual premium split monthly"),
        ("Gym", "Health", 60, 60, ""),
        ("Savings", "Future", 900, 900, "Automatic transfer"),
    ]
    budget.cells[at("A1")] = "Household Budget 2026"
    budget.merges = [CellRange(at("A1"), at("G1"))]
    budget.setFormat(CellFormat(fontSize: 18, bold: true, textColor: hex("44546A"), alignment: .center,
                                verticalAlignment: .center), at: at("A1"))
    budget.rowHeights[0] = 32
    budget.cells[at("A2")] = "Planned against actual spending, by category"
    budget.setFormat(CellFormat(italic: true, textColor: hex("7F7F7F")), at: at("A2"))
    let headers = ["Item", "Category", "Budget", "Actual", "Difference", "Share", "Notes"]
    for (column, title) in headers.enumerated() {
        let address = CellAddress(row: 3, column: column)
        budget.cells[address] = title
        budget.setFormat(CellFormat(bold: true, textColor: hex("FFFFFF"), fillColor: hex("4472C4"),
                                    border: CellBorder(bottom: BorderLine(.medium, color: hex("2F5597"))),
                                    alignment: column >= 2 && column <= 5 ? .right : .general), at: address)
    }
    let accounting = NumberFormatPreset.accounting.code
    for (i, row) in rows.enumerated() {
        let r = 4 + i
        let excelRow = r + 1
        budget.cells[CellAddress(row: r, column: 0)] = row.0
        budget.cells[CellAddress(row: r, column: 1)] = row.1
        budget.cells[CellAddress(row: r, column: 2)] = CellValue.number(row.2).displayText
        budget.cells[CellAddress(row: r, column: 3)] = CellValue.number(row.3).displayText
        budget.cells[CellAddress(row: r, column: 4)] = "=C\(excelRow)-D\(excelRow)"
        budget.cells[CellAddress(row: r, column: 5)] = "=D\(excelRow)/$D$13"
        if !row.4.isEmpty { budget.cells[CellAddress(row: r, column: 6)] = row.4 }
        for column in 2...4 { budget.setFormat(CellFormat(numberFormat: accounting), at: CellAddress(row: r, column: column)) }
        budget.setFormat(CellFormat(numberFormat: "0.0%"), at: CellAddress(row: r, column: 5))
        budget.setFormat(CellFormat(textColor: hex("595959"), wrapText: true, numberFormat: "@"), at: CellAddress(row: r, column: 6))
        if i % 2 == 1 {
            for column in 0...1 { budget.setFormat(CellFormat(fillColor: hex("F2F2F2")), at: CellAddress(row: r, column: column)) }
        }
    }
    budget.cells[at("A13")] = "Total"
    for column in ["C", "D", "E"] { budget.cells[at("\(column)13")] = "=SUBTOTAL(9,\(column)5:\(column)12)" }
    budget.cells[at("F13")] = "=SUM(F5:F12)"
    for column in 0...6 {
        var format = budget.formats[CellAddress(row: 12, column: column)] ?? CellFormat()
        format.bold = true
        format.border = CellBorder(top: BorderLine(.thin, color: hex("4472C4")), bottom: BorderLine(.double, color: hex("4472C4")))
        if (2...4).contains(column) { format.numberFormat = accounting }
        if column == 5 { format.numberFormat = "0%" }
        budget.setFormat(format, at: CellAddress(row: 12, column: column))
    }
    budget.cells[at("A15")] = "Largest overspend"
    budget.cells[at("C15")] = "=INDEX(A5:A12,MATCH(MIN(E5:E12),E5:E12,0))"
    budget.cells[at("A16")] = "Food spending"
    budget.cells[at("C16")] = "=SUMIFS(D5:D12,B5:B12,\"Food\")"
    budget.setFormat(CellFormat(numberFormat: "\"$\"#,##0.00"), at: at("C16"))
    budget.cells[at("A17")] = "Report date"
    budget.cells[at("C17")] = "46313"
    budget.setFormat(CellFormat(numberFormat: "dddd, mmmm d, yyyy"), at: at("C17"))
    budget.columnWidths = [0: 110, 1: 80, 2: 96, 3: 96, 4: 96, 5: 60, 6: 220]
    budget.frozenRows = 4
    budget.filter = AutoFilter(range: CellRange(at("A4"), at("G12")))
    budget.conditionalFormats = [
        ConditionalFormat(ranges: [CellRange(at("E5"), at("E12"))], rule: .cellIs(.lessThan, "0", nil, .lightRedFillDarkRedText)),
        ConditionalFormat(ranges: [CellRange(at("D5"), at("D12"))], rule: .dataBar(hex("638EC6"))),
        ConditionalFormat(ranges: [CellRange(at("F5"), at("F12"))], rule: .colorScale([
            ScaleStop(.min, color: hex("FCFCFF")), ScaleStop(.max, color: hex("63BE7B")),
        ])),
    ]

    var lookups = Sheet(name: "Lookups")
    let products: [(String, Double, Int)] = [("Apple", 0.5, 120), ("Banana", 0.25, 300), ("Cherry", 4, 18), ("Date", 6.5, 9)]
    for (title, column) in [("Product", "A"), ("Price", "B"), ("Stock", "C"), ("Value", "D")] {
        lookups.cells[at("\(column)1")] = title
        lookups.setFormat(CellFormat(bold: true, border: CellBorder(bottom: BorderLine())), at: at("\(column)1"))
    }
    for (i, product) in products.enumerated() {
        let row = i + 2
        lookups.cells[at("A\(row)")] = product.0
        lookups.cells[at("B\(row)")] = CellValue.number(product.1).displayText
        lookups.cells[at("C\(row)")] = String(product.2)
        lookups.cells[at("D\(row)")] = "=B\(row)*C\(row)*(1+TaxRate)"
        lookups.setFormat(CellFormat(numberFormat: "\"$\"#,##0.00"), at: at("B\(row)"))
        lookups.setFormat(CellFormat(numberFormat: "\"$\"#,##0.00"), at: at("D\(row)"))
    }
    let examples: [(String, String)] = [
        ("Price of Cherry (XLOOKUP)", "=XLOOKUP(\"Cherry\",A2:A5,B2:B5)"),
        ("Products in stock over 50", "=COUNTIFS(C2:C5,\">50\")"),
        ("Names, joined", "=TEXTJOIN(\", \",TRUE,A2:A5)"),
        ("Stock value with tax", "=SUM(D2:D5)"),
        ("Monthly payment on $20,000 at 6% over 5 years", "=PMT(6%/12,60,-20000)"),
    ]
    for (i, example) in examples.enumerated() {
        lookups.cells[CellAddress(row: 7 + i, column: 0)] = example.0
        lookups.cells[CellAddress(row: 7 + i, column: 3)] = example.1
    }
    lookups.setFormat(CellFormat(numberFormat: "\"$\"#,##0.00"), at: at("D11"))
    lookups.setFormat(CellFormat(numberFormat: "\"$\"#,##0.00"), at: at("D12"))
    lookups.cells[at("F1")] = "TaxRate"
    lookups.cells[at("G1")] = "0.08"
    lookups.setFormat(CellFormat(numberFormat: "0%"), at: at("G1"))
    lookups.columnWidths = [0: 120, 3: 160]

    var tour = Workbook(sheets: [budget, lookups])
    tour.definedNames = [DefinedName(name: "TaxRate", formula: "Lookups!$G$1")]
    do {
        try XLSXWriter.data(for: tour).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
        print("Wrote \(CommandLine.arguments[2])")
        exit(0)
    } catch {
        print("Could not write the tour: \(error.localizedDescription)")
        exit(1)
    }
}

if CommandLine.arguments.count > 1 {
    var unreadable = 0
    for path in CommandLine.arguments.dropFirst() {
        let name = (path as NSString).lastPathComponent
        do {
            let book = try XLSXReader.workbook(from: Data(contentsOf: URL(fileURLWithPath: path)))
            let calc = Calculator(workbook: book)
            var unsupported = Set<String>()
            var errors = 0
            var formulas = 0
            let pattern = try NSRegularExpression(pattern: "([A-Za-z_][A-Za-z0-9._]*)\\(")
            for (index, sheet) in book.sheets.enumerated() {
                for (address, raw) in sheet.cells where CellInput.isFormula(raw) {
                    formulas += 1
                    if case .error(let e) = calc.value(sheet: index, at: address) {
                        errors += 1
                        if ProcessInfo.processInfo.environment["FIGURES_VERBOSE"] != nil, errors <= 3 {
                            print("      \(e.rawValue) \(sheet.name)!\(address.a1) \(raw.prefix(100))")
                        }
                        if e == .name {
                            for match in pattern.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)) {
                                let fn = (raw as NSString).substring(with: match.range(at: 1)).uppercased()
                                if FunctionCatalog.info(fn) == nil { unsupported.insert(fn) }
                            }
                        }
                    }
                }
                // Render what the grid would show first, to exercise number formats and conditional formatting.
                for row in 0...min(sheet.maxRow ?? 0, 200) {
                    for column in 0...min(sheet.maxColumn ?? 0, 50) {
                        let address = CellAddress(row: row, column: column)
                        _ = calc.displayText(sheet: index, at: address)
                        _ = calc.conditionalFormatting(sheet: index, at: address)
                    }
                }
            }
            let sheets = book.sheets.map { s in
                "\(s.name): \(s.cells.count) cells, \(s.formats.count) styled, \(s.merges.count) merges, " +
                    "\(s.conditionalFormats.count) rules, \(s.rowHeights.count) row heights, \(s.columnWidths.count) widths" +
                    (s.filter != nil ? ", filter" : "") + (s.frozenRows > 0 ? ", frozen \(s.frozenRows)" : "")
            }
            print("OK  \(name) font=\(book.defaultFontName) \(CellValue.number(book.defaultFontSize).displayText)pt formulas=\(formulas) errors=\(errors)"
                  + (unsupported.isEmpty ? "" : " unsupported=\(unsupported.sorted().joined(separator: ","))"))
            for line in sheets { print("      " + line) }
        } catch {
            unreadable += 1
            print("ERR \(name): \(error.localizedDescription)")
        }
    }
    exit(unreadable == 0 ? 0 : 1)
}

var failures = 0
var passed = 0

func check<T: Equatable>(_ label: String, _ actual: T, _ expected: T, line: Int = #line) {
    if actual == expected {
        passed += 1
    } else {
        failures += 1
        print("FAIL line \(line) \(label): got \(actual), expected \(expected)")
    }
}

enum ColorCheck {
    static func tint(_ hex: String, _ tint: Double) -> String { ColorTint.apply(RGBColor(hex: hex)!, tint).hex }
}

func sheet(_ cells: [String: String], name: String = "Sheet1") -> Sheet {
    var sheet = Sheet(name: name)
    for (a1, raw) in cells { sheet.setInput(raw, at: CellAddress(a1: a1)!) }
    return sheet
}

func display(_ workbook: Workbook, _ a1: String, sheet: Int = 0) -> String {
    Calculator(workbook: workbook).displayText(sheet: sheet, at: CellAddress(a1: a1)!)
}

/// Evaluates one formula against a fixed data sheet.
let data = sheet([
    "A1": "1", "A2": "2", "A3": "3", "A4": "apple", "A5": "TRUE",
    "B1": "10", "B2": "20", "B3": "30", "B4": "Banana", "B5": "",
    "C1": "a", "C2": "b", "C3": "c",
])
func eval(_ formula: String) -> String {
    var s = data
    s.setInput(formula, at: CellAddress(a1: "Z1")!)
    return display(Workbook(sheets: [s]), "Z1")
}

// Addresses
check("column name", CellAddress.columnName(0), "A")
check("column name", CellAddress.columnName(25), "Z")
check("column name", CellAddress.columnName(26), "AA")
check("column name", CellAddress.columnName(16_383), "XFD")
check("parse", CellAddress(a1: "$AB$12")!, CellAddress(row: 11, column: 27))
check("parse invalid", CellAddress(a1: "A0") == nil, true)
check("parse beyond XFD", CellAddress(a1: "XFE1") == nil, true)

// Literal input
check("number", CellInput.literalValue("1,234.5"), CellValue.number(1234.5))
check("percent", CellInput.literalValue("12%"), CellValue.number(0.12))
check("apostrophe", CellInput.literalValue("'00123"), CellValue.text("00123"))
check("nan is text", CellInput.literalValue("nan"), CellValue.text("nan"))
check("raw round trip", CellInput.rawInput(for: .text("00123")), "'00123")
check("raw round trip", CellInput.rawInput(for: .text("=1+1")), "'=1+1")

// Arithmetic and precedence
check("add", eval("=1+2*3"), "7")
check("parens", eval("=(1+2)*3"), "9")
check("negation before power", eval("=-2^2"), "4")
check("power left assoc", eval("=2^3^2"), "64")
check("percent", eval("=50%"), "0.5")
check("float noise", eval("=0.1+0.2"), "0.3")
check("div zero", eval("=1/0"), "#DIV/0!")
check("text arithmetic", eval("=A4+1"), "#VALUE!")
check("numeric text", eval("=\"3\"*2"), "6")
check("concat", eval("=A4&\"-\"&A1"), "apple-1")
check("compare text", eval("=\"a\"=\"A\""), "TRUE")
check("compare types", eval("=1<\"a\""), "TRUE")
check("empty ref is 0", eval("=Y9"), "0")
check("empty concat", eval("=Y9&\"x\""), "x")
check("lowercase refs", eval("=a1+b1"), "11")

// Functions
check("sum", eval("=SUM(A1:A5)"), "6")
check("sum direct", eval("=SUM(1,\"2\",TRUE)"), "4")
check("sum column", eval("=SUM(B:B)"), "60")
check("average", eval("=AVERAGE(A1:B3)"), "11")
check("min max", eval("=MIN(B1:B3)+MAX(A1:A3)"), "13")
check("count", eval("=COUNT(A1:A5)"), "3")
check("counta", eval("=COUNTA(A1:A5)"), "5")
check("countblank", eval("=COUNTBLANK(A1:B6)"), "3")
check("if", eval("=IF(A1>0,\"pos\",\"neg\")"), "pos")
check("if no else", eval("=IF(A1>5,1)"), "FALSE")
check("iferror", eval("=IFERROR(1/0,\"oops\")"), "oops")
check("and or", eval("=AND(A1,OR(FALSE,TRUE))"), "TRUE")
check("round", eval("=ROUND(2.675,2)"), "2.68")
check("roundup", eval("=ROUNDUP(-1.21,1)"), "-1.3")
check("rounddown", eval("=ROUNDDOWN(1.29,1)"), "1.2")
check("mod sign", eval("=MOD(-3,2)"), "1")
check("sqrt neg", eval("=SQRT(-1)"), "#NUM!")
check("text fns", eval("=UPPER(LEFT(A4,3))&LOWER(RIGHT(B4,2))&MID(\"abcdef\",2,3)"), "APPnabcd")
check("trim", eval("=TRIM(\"  a   b  \")"), "a b")
check("len", eval("=LEN(B4)"), "6")
check("concat range", eval("=CONCAT(C1:C3)"), "abc")
check("countif", eval("=COUNTIF(B1:B3,\">15\")"), "2")
check("countif wildcard", eval("=COUNTIF(A1:B4,\"*an*\")"), "1")
check("sumif", eval("=SUMIF(A1:A3,\">=2\",B1:B3)"), "50")
check("averageif", eval("=AVERAGEIF(A1:A3,\"<>2\",B1:B3)"), "20")
check("vlookup exact", eval("=VLOOKUP(2,A1:B3,2,FALSE)"), "20")
check("vlookup approx", eval("=VLOOKUP(2.5,A1:B3,2)"), "20")
check("vlookup missing", eval("=VLOOKUP(9,A1:B3,2,FALSE)"), "#N/A")
check("match", eval("=MATCH(\"b\",C1:C3,0)"), "2")
check("index", eval("=INDEX(A1:B3,3,2)"), "30")
check("index match", eval("=INDEX(B1:B3,MATCH(3,A1:A3,0))"), "30")
check("unknown fn", eval("=NOPE(1)"), "#NAME?")
check("bad syntax", eval("=1+"), "#NAME?")
check("xlfn prefix", eval("=_xlfn.CONCAT(\"a\",\"b\")"), "ab")

// Dependencies, cycles, sheets
let chain = Workbook(sheets: [sheet(["A1": "=B1*2", "B1": "=C1+1", "C1": "4"])])
check("chain", display(chain, "A1"), "10")
let cycle = Workbook(sheets: [sheet(["A1": "=B1", "B1": "=A1+1"])])
check("cycle", display(cycle, "A1"), "#CIRC!")
let twoSheets = Workbook(sheets: [
    sheet(["A1": "=Data!B2*2+'My Data'!A1"]),
    sheet(["B2": "21"], name: "Data"),
    sheet(["A1": "1"], name: "My Data"),
])
check("cross sheet", display(twoSheets, "A1"), "43")
check("missing sheet", eval("=Nope!A1"), "#REF!")

// Formats
var formatted = sheet(["A1": "1234.5", "A2": "-0.1234", "A3": "46313"])
formatted.setFormat(CellFormat(numberFormat: NumberFormatPreset.currency.code), at: CellAddress(a1: "A1")!)
formatted.setFormat(CellFormat(numberFormat: NumberFormatPreset.percentage.code), at: CellAddress(a1: "A2")!)
formatted.setFormat(CellFormat(numberFormat: NumberFormatPreset.isoDate.code), at: CellAddress(a1: "A3")!)
let formatBook = Workbook(sheets: [formatted])
check("currency", display(formatBook, "A1"), "$1,234.50")
check("percent", display(formatBook, "A2"), "-12.34%")
check("date", display(formatBook, "A3"), "2026-10-18")

// Formula editing
check("shift", FormulaText.shifted("=A1+$B$2+B$3+$C4", rows: 1, columns: 1), "=B2+$B$2+C$3+$C5")
check("shift off sheet", FormulaText.shifted("=A1*2", rows: -1, columns: 0), "=#REF!*2")
check("shift keeps strings", FormulaText.shifted("=\"A1\"&A1", rows: 1, columns: 0), "=\"A1\"&A2")
check("shift columns", FormulaText.shifted("=SUM(A:A)", rows: 3, columns: 1), "=SUM(B:B)")
check("shift skips functions", FormulaText.shifted("=LOG10(A1)", rows: 1, columns: 0), "=LOG10(A2)")
check("normalize", FormulaText.normalized("=sum(a1:b2"), "=SUM(A1:B2)")
check("ref error parses", eval("=#REF!+1"), "#REF!")

// CSV
let csvRows = CSV.rows("a,\"b,c\",\"d\"\"e\"\r\n1,,3\n")
check("csv", csvRows, [["a", "b,c", "d\"e"], ["1", "", "3"]])
check("csv encode", CSV.encode(csvRows), "a,\"b,c\",\"d\"\"e\"\r\n1,,3")

// XLSX round trip
var original = sheet(["A1": "Item", "B1": "Price", "A2": "Pen", "B2": "1.5", "A3": "Book",
                      "B3": "12", "A4": "Total", "B4": "=SUM(B2:B3)", "C1": "'007",
                      "C2": "TRUE", "C3": "=CONCAT(A2,\" & \",A3)", "D1": "<tag> & \"quotes\""])
original.setFormat(CellFormat(bold: true, alignment: .center), at: CellAddress(a1: "A1")!)
original.setFormat(CellFormat(numberFormat: NumberFormatPreset.currency.code), at: CellAddress(a1: "B4")!)
original.columnWidths[0] = 120
let second = sheet(["A1": "=Sheet1!B4*2"], name: "Summary")
let book = Workbook(sheets: [original, second])
let xlsx = XLSXWriter.data(for: book)
do {
    let reread = try XLSXReader.workbook(from: xlsx)
    check("sheet names", reread.sheets.map(\.name), ["Sheet1", "Summary"])
    check("cells", reread.sheets[0].cells, original.cells)
    check("formats", reread.sheets[0].formats, original.formats)
    check("widths", reread.sheets[0].columnWidths[0].map { ($0 * 10).rounded() / 10 } ?? 0, 120.0)
    check("xlfn written", String(decoding: xlsx, as: UTF8.self).contains("_xlfn.CONCAT"), false) // parts are deflated
    check("xlfn round trip", FormulaText.shifted(reread.sheets[0].cells[CellAddress(a1: "C3")!]!, rows: 0, columns: 0), "=CONCAT(A2,\" & \",A3)")
    check("cross-sheet value", display(reread, "A1", sheet: 1), "27")
    check("formatted total", display(reread, "B4"), "$13.50")
} catch {
    failures += 1
    print("FAIL xlsx round trip: \(error)")
}
// Extended functions
let people = sheet([
    "A1": "Name", "B1": "Dept", "C1": "Pay", "D1": "Start",
    "A2": "ann", "B2": "Ops", "C2": "100", "D2": "=DATE(2024,1,31)",
    "A3": "bob", "B3": "Dev", "C3": "300", "D3": "=DATE(2023,6,15)",
    "A4": "cy", "B4": "Dev", "C4": "200", "D4": "=DATE(2025,2,28)",
])
func evalPeople(_ formula: String) -> String {
    var s = people
    s.setInput(formula, at: CellAddress(a1: "Z9")!)
    return display(Workbook(sheets: [s]), "Z9")
}
check("sumifs", evalPeople("=SUMIFS(C2:C4,B2:B4,\"Dev\",C2:C4,\">250\")"), "300")
check("countifs", evalPeople("=COUNTIFS(B2:B4,\"Dev\")"), "2")
check("averageifs", evalPeople("=AVERAGEIFS(C2:C4,B2:B4,\"Dev\")"), "250")
check("maxifs", evalPeople("=MAXIFS(C2:C4,B2:B4,\"Ops\")"), "100")
check("ifs", evalPeople("=IFS(C2>200,\"high\",C2>50,\"mid\")"), "mid")
check("switch", evalPeople("=SWITCH(B3,\"Ops\",1,\"Dev\",2,0)"), "2")
check("switch default", evalPeople("=SWITCH(\"x\",\"Ops\",1,9)"), "9")
check("choose", evalPeople("=CHOOSE(2,\"a\",\"b\")"), "b")
check("xlookup", evalPeople("=XLOOKUP(\"cy\",A2:A4,C2:C4)"), "200")
check("xlookup missing", evalPeople("=XLOOKUP(\"zz\",A2:A4,C2:C4,\"none\")"), "none")
check("hlookup", evalPeople("=HLOOKUP(\"Pay\",A1:D4,3,FALSE)"), "300")
check("textjoin", evalPeople("=TEXTJOIN(\", \",TRUE,A2:A4)"), "ann, bob, cy")
check("sumproduct", eval("=SUMPRODUCT(A1:A3,B1:B3)"), "140")
check("median", evalPeople("=MEDIAN(C2:C4)"), "200")
check("stdev", evalPeople("=ROUND(STDEV.S(C2:C4),4)"), "100")
check("large small", evalPeople("=LARGE(C2:C4,1)-SMALL(C2:C4,1)"), "200")
check("rank", evalPeople("=RANK(200,C2:C4)"), "2")
check("ceiling floor", eval("=CEILING(4.1,0.5)+FLOOR(4.9,1)"), "8.5")
check("date parts", evalPeople("=YEAR(D2)&\"-\"&MONTH(D2)&\"-\"&DAY(D2)"), "2024-1-31")
check("edate clamps", evalPeople("=TEXT(EDATE(D2,1),\"yyyy-mm-dd\")"), "2024-02-29")
check("eomonth", evalPeople("=TEXT(EOMONTH(D3,0),\"dd/mm/yyyy\")"), "30/06/2023")
check("weekday", evalPeople("=WEEKDAY(D2)"), "4")
check("days", evalPeople("=DAYS(D2,D3)"), "230")
check("text number", eval("=TEXT(1234.567,\"$#,##0.00\")"), "$1,234.57")
check("text percent", eval("=TEXT(0.256,\"0.0%\")"), "25.6%")
check("substitute", eval("=SUBSTITUTE(\"a-b-c\",\"-\",\"+\",2)"), "a-b+c")
check("replace", eval("=REPLACE(\"abcdef\",2,3,\"X\")"), "aXef")
check("find search", eval("=FIND(\"c\",\"abcabc\",4)+SEARCH(\"B\",\"abc\")"), "8")
check("proper", eval("=PROPER(\"hello wORLD\")"), "Hello World")
check("is functions", eval("=AND(ISBLANK(Y1),ISNUMBER(A1),ISTEXT(A4),ISERROR(1/0),ISNA(NA()))"), "TRUE")
check("row column", eval("=ROW()*100+COLUMN(C5)"), "103")
check("trig", eval("=ROUND(SIN(PI()/6)+COS(0)+DEGREES(ATAN2(1,1)),6)"), "46.5")
check("trunc mround", eval("=TRUNC(-2.789,1)+MROUND(10,3)"), "6.3")
check("even odd fact", eval("=EVEN(1.5)+ODD(2)+FACT(5)"), "125")
check("log gcd lcm", eval("=LOG(8,2)+GCD(12,18)+LCM(4,6)"), "21")
check("mode", eval("=MODE(1,2,2,3)"), "2")
check("time parts", eval("=HOUR(TIME(13,45,30))*10000+MINUTE(TIME(13,45,30))*100+SECOND(TIME(13,45,30))"), "134530")
check("workday", evalPeople("=TEXT(WORKDAY(D2,3),\"yyyy-mm-dd\")"), "2024-02-05")
check("networkdays", evalPeople("=NETWORKDAYS(DATE(2024,1,1),DATE(2024,1,31))"), "23")
check("pmt", eval("=ROUND(PMT(0.05/12,360,200000),2)"), "-1073.64")
check("fv", eval("=ROUND(FV(0.06/12,10,-200,-500,1),2)"), "2581.4")
check("pv", eval("=ROUND(PV(0.08/12,240,500),2)"), "-59777.15")
check("nper", eval("=ROUND(NPER(0.01,-100,-1000,10000,1),2)"), "59.67")
check("npv", eval("=ROUND(NPV(0.1,-10000,3000,4200,6800),2)"), "1188.44")
check("irr array", eval("=ROUND(IRR({-70000,12000,15000,18000,21000,26000}),4)"), "0.0866")
check("rate", eval("=ROUND(RATE(48,-200,8000),6)"), "0.007701")
check("base conversion", eval("=HEX2DEC(\"FF\")+BIN2DEC(\"1111111111\")"), "254")
check("dec2hex", eval("=DEC2HEX(255,4)&DEC2BIN(-1)"), "00FF1111111111")
check("indirect", eval("=SUM(INDIRECT(\"B1:B3\"))+INDIRECT(\"A\"&2)"), "62")
check("offset", eval("=SUM(OFFSET(A1,1,1,2,1))"), "50")
check("lookup", eval("=LOOKUP(2.5,A1:A3,B1:B3)"), "20")
check("xmatch", eval("=XMATCH(25,B1:B3,-1)"), "2")
check("clean t n", eval("=LEN(CLEAN(CHAR(7)&\"ab\"))&T(5)&N(TRUE)"), "21")
var subtotalSheet = sheet(["A1": "1", "A2": "2", "A3": "=SUBTOTAL(9,A1:A2)", "A4": "4", "A5": "=SUBTOTAL(9,A1:A4)", "A6": "=SUBTOTAL(109,A1:A4)"])
subtotalSheet.hiddenRows = [3]
let subtotalBook = Workbook(sheets: [subtotalSheet])
check("subtotal skips subtotals", display(subtotalBook, "A5"), "7")
check("subtotal 109 skips hidden", display(subtotalBook, "A6"), "3")
var named = Workbook(sheets: [
    sheet(["A1": "=Rate*Amount", "A2": "=SUM(Totals)", "A3": "=IF(A1>5,5,)", "A4": "=SUM({1,2;3,4})", "A5": "=SUM(2:2)",
           "B2": "7", "C2": "8", "A6": "=SUM(Jan:Feb!B1)", "A7": "=IRR(Flows)"]),
    sheet(["B1": "10", "C1": "0.5", "D1": "-100", "D2": "60", "D3": "60"], name: "Jan"),
    sheet(["B1": "20"], name: "Feb"),
])
named.definedNames = [DefinedName(name: "Rate", formula: "Jan!$C$1"), DefinedName(name: "Amount", formula: "4"),
                      DefinedName(name: "Totals", formula: "Jan!$B$1:$B$2"), DefinedName(name: "Flows", formula: "Jan!$D$1:$D$3")]
check("defined names", display(named, "A1"), "2")
check("defined range name", display(named, "A2"), "10")
check("empty argument", display(named, "A3"), "0")
check("array constant", display(named, "A4"), "10")
check("row range", display(named, "A5"), "25")
check("3D reference", display(named, "A6"), "30")
check("irr range", display(named, "A7").prefix(6), "0.1306")
check("row range shift", FormulaText.shifted("=SUM(2:2)", rows: 1, columns: 0), "=SUM(3:3)")
do {
    let reread = try XLSXReader.workbook(from: XLSXWriter.data(for: named))
    check("names round trip", reread.definedNames, named.definedNames)
    check("names evaluate after reload", display(reread, "A1"), "2")
} catch {
    failures += 1
    print("FAIL names round trip: \(error)")
}
for info in FunctionCatalog.all {
    check("catalog \(info.name) is implemented", eval("=\(info.name)()") != CellError.name.rawValue, true)
}

// Excel number format codes
func fmt(_ value: Double, _ code: String) -> String { ExcelNumberFormat.format(.number(value), code: code).text }
check("nf general", fmt(1234.5, "General"), "1234.5")
check("nf integer", fmt(1234.5, "0"), "1235")
check("nf decimals", fmt(-1234.567, "#,##0.00"), "-1,234.57")
check("nf optional", fmt(3.1, "#.##"), "3.1")
check("nf leading zeros", fmt(42, "00000"), "00042")
check("nf two sections", fmt(-5, "0.0;(0.0)"), "(5.0)")
check("nf three sections zero", fmt(0, "0;-0;\"zero\""), "zero")
check("nf red color", ExcelNumberFormat.format(.number(-3), code: "0;[Red]0").color, RGBColor(red: 255, green: 0, blue: 0))
check("nf percent", fmt(0.1234, "0.0%"), "12.3%")
check("nf scaling", fmt(1234567, "#,##0.0,,\"M\""), "1.2M")
check("nf literal", fmt(5, "0\" kg\""), "5 kg")
check("nf currency locale", fmt(9.5, "[$€-407]#,##0.00"), "€9.50")
check("nf accounting", fmt(1234.5, NumberFormatPreset.accounting.code), " $ 1,234.50 ")
check("nf accounting negative", fmt(-1234.5, NumberFormatPreset.accounting.code), " $ (1,234.50)")
check("nf accounting zero", fmt(0, NumberFormatPreset.accounting.code), " $ -   ")
check("nf scientific", fmt(12345, "0.00E+00"), "1.23E+04")
check("nf engineering", fmt(12345, "##0.0E+0"), "12.3E+3")
check("nf fraction", fmt(1.75, "# ?/?"), "1 3/4")
check("nf fraction fixed", fmt(0.3, "# ?/8"), "2/8")
check("nf phone", fmt(5551234, "000-0000"), "555-1234")
check("nf condition", fmt(150, "[>100]\"big\";\"small\""), "big")
check("nf date", fmt(46313, "m/d/yyyy"), "10/18/2026")
check("nf date names", fmt(46313, "dddd, mmmm d, yyyy"), "Sunday, October 18, 2026")
check("nf date short", fmt(46313, "d-mmm-yy"), "18-Oct-26")
check("nf time", fmt(0.6875, "h:mm AM/PM"), "4:30 PM")
check("nf minutes", fmt(0.6875, "hh:mm:ss"), "16:30:00")
check("nf month vs minute", fmt(46313.5, "mm/dd hh:mm"), "10/18 12:00")
check("nf elapsed", fmt(1.5, "[h]:mm"), "36:00")
check("nf text section", ExcelNumberFormat.format(.text("abc"), code: "0;0;0;\"<\"@\">\"").text, "<abc>")
check("nf at", fmt(12.5, "@"), "12.5")
check("nf builtin", ExcelNumberFormat.builtIn[14], "m/d/yyyy")
check("nf more decimals", ExcelNumberFormat.adjustingDecimals("#,##0", by: 1), "#,##0.0")
check("nf fewer decimals", ExcelNumberFormat.adjustingDecimals("0.0%", by: -1), "0%")
check("nf decimals two sections", ExcelNumberFormat.adjustingDecimals("0.00;(0.00)", by: 1), "0.000;(0.000)")
check("theme tint", ColorCheck.tint("4472C4", 0.3999), "8FAADC")
check("theme tint dark", ColorCheck.tint("ED7D31", -0.2499), "C55A11")

// Incremental recalculation must always agree with calculating from scratch.
do {
    var seed: UInt64 = 0x5EED
    func next(_ bound: Int) -> Int {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Int((seed >> 33) % UInt64(bound))
    }
    var book = Workbook(sheets: [Sheet(name: "Main"), Sheet(name: "Other")])
    book.definedNames = [DefinedName(name: "Base", formula: "Other!$A$1")]
    let formulas = [
        "=A1+B2", "=SUM(A:A)", "=SUM(A1:C5)*2", "=Other!A1+Other!B3", "=VLOOKUP(3,A1:B10,2,FALSE)",
        "=COUNTIF(B:B,\">2\")", "=IF(A2>5,C3,D4)", "=Base*2", "=SUMIFS(B1:B10,A1:A10,\">1\")",
        "=INDEX(A1:A10,MATCH(4,B1:B10,0))", "=MAX(Other!A1:B5)", "=CONCAT(A1:A4)", "=SUBTOTAL(9,A1:A10)",
        "=IFERROR(1/C2,0)", "=OFFSET(A1,1,1)", "=INDIRECT(\"B\"&2)", "=C1+D1", "=AVERAGE(D:D)",
    ]
    var calc = Calculator(workbook: book)
    var mismatches = 0
    for step in 0..<300 {
        let sheet = next(4) == 0 ? 1 : 0
        let address = CellAddress(row: next(10), column: next(5))
        switch next(10) {
        case 0...4: book.sheets[sheet].setInput(String(next(20) - 5), at: address)
        case 5...7: book.sheets[sheet].setInput(formulas[next(formulas.count)], at: address)
        case 8: book.sheets[sheet].setInput("", at: address)
        default: book.sheets[sheet].setInput("text\(next(3))", at: address)
        }
        let previous = calc
        calc = Calculator.updating(previous, for: book)
        // Read in a shuffled order so cached and fresh values meet in different sequences.
        let fresh = Calculator(workbook: book)
        let addresses = (0..<2).flatMap { s in (0..<10).flatMap { r in (0..<5).map { (s, CellAddress(row: r, column: $0)) } } }
        for (s, a) in addresses.sorted(by: { _, _ in next(2) == 0 }) where calc.value(sheet: s, at: a) != fresh.value(sheet: s, at: a) {
            mismatches += 1
            if mismatches <= 3 { print("FAIL incremental step \(step) \(book.sheets[s].name)!\(a.a1): \(calc.value(sheet: s, at: a)) vs \(fresh.value(sheet: s, at: a))") }
        }
    }
    check("incremental recalculation matches full", mismatches, 0)
}

// Numbers-style features: controls, autofill, category summaries, templates
do {
    func at(_ a1: String) -> CellAddress { CellAddress(a1: a1)! }
    var controlled = sheet(["A1": "TRUE", "B1": "4", "C1": "Medium", "D1": "3", "E1": "50", "F1": "x"])
    controlled.controls = [at("A1"): .checkbox, at("A2"): .checkbox, at("B1"): .rating, at("C1"): .popUp(.items(["Low", "Medium", "High"])),
                           at("D1"): .stepper(minimum: 0, maximum: 10, step: 1), at("E1"): .slider(minimum: 0, maximum: 100, step: 5),
                           at("F1"): .popUp(.range("$H$1:$H$3")), at("G1"): .popUp(.items(["a,b", "c"]))]
    controlled.cells[at("H1")] = "red"
    controlled.cells[at("H2")] = "green"
    controlled.cells[at("H3")] = "red"
    let reread = try XLSXReader.workbook(from: XLSXWriter.data(for: Workbook(sheets: [controlled])))
    check("controls round trip", reread.sheets[0].controls, controlled.controls)
    check("pop-up range options", Calculator(workbook: reread).popUpOptions(.range("$H$1:$H$3"), sheet: 0), ["red", "green"])
    check("rating input clamps", CellControl.rating.input(for: .number(9)), "5")
    check("checkbox input", CellControl.checkbox.input(for: .number(1)), "TRUE")
    check("stepper clamps", CellControl.stepper(minimum: 0, maximum: 10, step: 1).input(for: .number(-3)), "0")

    var fill = Workbook(sheets: [sheet([
        "A1": "1", "A2": "3", "B1": "Item 7", "C1": "Mon", "D1": "JANUARY", "E1": "=A1*2", "F1": "x", "F2": "y",
        "G1": "46313", "H1": "Q09",
    ])])
    fill.sheets[0].setFormat(CellFormat(numberFormat: "m/d/yyyy"), at: at("G1"))
    fill.sheets[0].controls[at("F1")] = .checkbox
    fill.autofill(sheet: 0, source: CellRange(at("A1"), at("A2")), target: CellRange(at("A1"), at("A5")))
    for column in ["B", "C", "D", "E", "G", "H"] {
        fill.autofill(sheet: 0, source: CellRange(at("\(column)1"), at("\(column)1")), target: CellRange(at("\(column)1"), at("\(column)4")))
    }
    fill.autofill(sheet: 0, source: CellRange(at("F1"), at("F2")), target: CellRange(at("F1"), at("F5")))
    let cells = fill.sheets[0].cells
    check("fill numbers step", (1...5).map { cells[at("A\($0)")]! }, ["1", "3", "5", "7", "9"])
    check("fill numbered text", (1...4).map { cells[at("B\($0)")]! }, ["Item 7", "Item 8", "Item 9", "Item 10"])
    check("fill weekdays", (1...4).map { cells[at("C\($0)")]! }, ["Mon", "Tue", "Wed", "Thu"])
    check("fill months keep case", (1...3).map { cells[at("D\($0)")]! }, ["JANUARY", "FEBRUARY", "MARCH"])
    check("fill formulas shift", cells[at("E3")], "=A3*2")
    check("fill dates by day", display(fill, "G3"), "10/20/2026")
    check("fill keeps zero padding", cells[at("H4")], "Q12")
    check("fill repeats text", (1...5).map { cells[at("F\($0)")]! }, ["x", "y", "x", "y", "x"])
    check("fill copies controls", fill.sheets[0].controls[at("F3")], .checkbox)
    fill.autofill(sheet: 0, source: CellRange(at("C1"), at("C1")), target: CellRange(at("C1"), at("E1")))
    check("fill right", ["D1", "E1"].map { fill.sheets[0].cells[at($0)]! }, ["Tue", "Wed"])

    var sales = Workbook(sheets: [sheet([
        "A1": "Region", "B1": "Rep", "C1": "Amount",
        "A2": "West", "B2": "Ann", "C2": "100", "A3": "East", "B3": "Bob", "C3": "50",
        "A4": "West", "B4": "Cy", "C4": "300", "A5": "North", "B5": "Di", "C5": "20",
    ], name: "Sales Data")])
    let summaryIndex = sales.addCategorySummary(sheet: 0, table: CellRange(at("A1"), at("C5")), hasHeader: true, groupBy: 0)
    check("summary sheet", summaryIndex.map { sales.sheets[$0].name }, "Region Summary")
    if let summaryIndex {
        check("summary groups", (5...7).map { display(sales, "A\($0)", sheet: summaryIndex) }, ["East", "North", "West"])
        check("summary counts", (5...7).map { display(sales, "B\($0)", sheet: summaryIndex) }, ["1", "1", "2"])
        check("summary totals", display(sales, "C7", sheet: summaryIndex), "400.00")
        check("summary averages", display(sales, "D7", sheet: summaryIndex), "200.00")
        check("summary grand total", display(sales, "C8", sheet: summaryIndex), "470.00")
        sales.sheets[0].cells[at("C2")] = "1000"
        check("summary stays live", display(sales, "C7", sheet: summaryIndex), "1,300.00")
    }

    var templates = Workbook()
    for template in SheetTemplate.allCases {
        let index = templates.addSheet(from: template)
        let calc = Calculator(workbook: templates)
        let errors = templates.sheets[index].cells.keys.filter { if case .error = calc.value(sheet: index, at: $0) { true } else { false } }
        check("template \(template.rawValue) has no errors", errors.map(\.a1).sorted(), [])
    }
    check("template names unique", templates.addSheet(from: .budget) > 0 && templates.sheets.last?.name == "Personal Budget 2", true)
    let templateFile = try XLSXReader.workbook(from: XLSXWriter.data(for: templates))
    check("templates round trip controls", templateFile.sheets.map(\.controls), templates.sheets.map(\.controls))
} catch {
    failures += 1
    print("FAIL Numbers features: \(error)")
}

// Canvas objects
do {
    func at(_ a1: String) -> CellAddress { CellAddress(a1: a1)! }
    var page = sheet(["A1": "Month", "B1": "Sales", "A2": "Jan", "B2": "10", "A3": "Feb", "B3": "25"])
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02])
    page.canvas = [
        CanvasObject(x: 300, y: 20, width: 320, height: 200, kind: .chart(.column, range: CellRange(at("A1"), at("B3")), title: "Sales")),
        CanvasObject(x: 10, y: 260, width: 200, height: 60, kind: .text("Notes & <ideas>"), fill: RGBColor(hex: "FFF2CC"), fontSize: 18, bold: true),
        CanvasObject(x: 220, y: 260, width: 80, height: 80, kind: .shape(.oval), fill: RGBColor(hex: "70AD47"), stroke: RGBColor(hex: "000000")),
        CanvasObject(x: 320, y: 260, width: 50, height: 50, kind: .image(png)),
    ]
    let book = Workbook(sheets: [page])
    let reread = try XLSXReader.workbook(from: XLSXWriter.data(for: book))
    check("canvas round trip", reread.sheets[0].canvas, page.canvas)
    let data = Calculator(workbook: book).chartData(CellRange(at("A1"), at("B3")), sheet: 0)
    check("chart data categories", data.categories, ["Jan", "Feb"])
    check("chart data series", data.series.map(\.name), ["Sales"])
    check("chart data values", data.series.first?.values, [10, 25])
    var moved = book
    moved.apply(.insertRows(at: 0, count: 2), toSheet: 0)
    if case .chart(_, let range, _) = moved.sheets[0].canvas[0].kind {
        check("chart range follows inserted rows", range.a1, "A3:B5")
    } else {
        check("chart kind kept", false, true)
    }
} catch {
    failures += 1
    print("FAIL canvas: \(error)")
}

// Formula autocomplete
check("assist prefix", FormulaAssist(text: "=SUM(A1)+VL").suggestions.map(\.name), ["VLOOKUP"])
check("assist ref is not a name", FormulaAssist(text: "=A1").suggestions.isEmpty, true)
check("assist inside string", FormulaAssist(text: "=\"VL").suggestions.isEmpty, true)
check("assist signature", FormulaAssist(text: "=IF(A1>2, SUM(").currentFunction?.name, "SUM")
check("assist after close", FormulaAssist(text: "=IF(SUM(A1),").currentFunction?.name, "IF")

// Structural edits
var structure = Workbook(sheets: [
    sheet(["A1": "1", "A2": "2", "A3": "3", "B1": "=SUM(A1:A3)", "B2": "=A3*2", "B3": "=$A$2"]),
    sheet(["A1": "=Sheet1!A3+1"], name: "Other"),
])
structure.apply(.insertRows(at: 1, count: 2), toSheet: 0)
check("insert rows grows range", structure.sheets[0].cells[CellAddress(a1: "B1")!], "=SUM(A1:A5)")
check("insert rows moves refs", structure.sheets[0].cells[CellAddress(a1: "B4")!], "=A5*2")
check("insert rows moves absolute", structure.sheets[0].cells[CellAddress(a1: "B5")!], "=$A$4")
check("insert rows other sheet", structure.sheets[1].cells[CellAddress(a1: "A1")!], "=Sheet1!A5+1")
check("insert rows value", display(structure, "B1"), "6")
structure.apply(.deleteRows(at: 4, count: 1), toSheet: 0)
check("delete rows shrinks range", structure.sheets[0].cells[CellAddress(a1: "B1")!], "=SUM(A1:A4)")
check("delete rows ref error", structure.sheets[1].cells[CellAddress(a1: "A1")!], "=#REF!+1")
check("delete rows ref error value", display(structure, "A1", sheet: 1), "#REF!")
var columns = Workbook(sheets: [sheet(["A1": "5", "C1": "=A1+B1", "D1": "=SUM(A:B)"])])
columns.apply(.insertColumns(at: 1, count: 1), toSheet: 0)
check("insert column", columns.sheets[0].cells[CellAddress(a1: "D1")!], "=A1+C1")
check("insert column range", columns.sheets[0].cells[CellAddress(a1: "E1")!], "=SUM(A:C)")
columns.apply(.deleteColumns(at: 0, count: 1), toSheet: 0)
check("delete column", columns.sheets[0].cells[CellAddress(a1: "C1")!], "=#REF!+B1")

// Sorting, duplicates, filters, find & replace
var sortable = Workbook(sheets: [sheet([
    "A1": "Name", "B1": "Score", "C1": "Double",
    "A2": "b", "B2": "20", "C2": "=B2*2",
    "A3": "a", "B3": "30", "C3": "=B3*2",
    "A4": "c", "B4": "", "C4": "=B4*2",
    "A5": "a", "B5": "30", "C5": "=B5*2",
])])
let table = sortable.sheets[0].currentRegion(around: CellAddress(a1: "B3")!)
check("current region", table.a1, "A1:C5")
sortable.sort(sheet: 0, range: table, byColumn: 1, ascending: false, hasHeader: true)
check("sort desc", (2...5).map { display(sortable, "A\($0)") }, ["a", "a", "b", "c"])
check("sort moves formulas", sortable.sheets[0].cells[CellAddress(a1: "C4")!], "=B4*2")
check("sort formula value", display(sortable, "C4"), "40")
check("remove duplicates", sortable.removeDuplicates(sheet: 0, range: table, hasHeader: true), 1)
check("after duplicates", (2...5).map { display(sortable, "A\($0)") }, ["a", "b", "c", ""])
sortable.sheets[0].filter = AutoFilter(range: CellRange(CellAddress(a1: "A1")!, CellAddress(a1: "C4")!), allowedValues: [0: ["a", "c"]])
check("filter hides", Calculator(workbook: sortable).hiddenRows(sheet: 0), [2])
check("find", Calculator(workbook: sortable).find("dou", sheet: 0, after: CellAddress(a1: "A1")!, matchCase: false)?.a1, "C1")
check("find case", Calculator(workbook: sortable).find("C", sheet: 0, after: CellAddress(a1: "A1")!, matchCase: true)?.a1, nil)
check("replace", sortable.replace("a", with: "z", sheet: 0, cells: Array(sortable.sheets[0].cells.keys), matchCase: true), 2)
check("replaced", sortable.sheets[0].cells[CellAddress(a1: "A1")!], "Nzme")

// Rich formats and view settings round trip through XLSX
var styled = sheet(["A1": "Header", "A2": "1234.5678", "A3": "0.5", "A4": "x", "A5": "y", "B1": "=A2*2"])
styled.setFormat(CellFormat(fontName: "Georgia", fontSize: 14, bold: true, underline: true, textColor: RGBColor(hex: "C00000"),
                            fillColor: RGBColor(hex: "FFFF00"), border: .all(BorderLine(.thin)), alignment: .center,
                            verticalAlignment: .top, wrapText: true, indent: 2), at: CellAddress(a1: "A1")!)
styled.setFormat(CellFormat(numberFormat: "#,##0.000"), at: CellAddress(a1: "A2")!)
styled.setFormat(CellFormat(strikethrough: true, border: CellBorder(bottom: BorderLine(.double, color: RGBColor(hex: "0070C0"))),
                            numberFormat: "0%"), at: CellAddress(a1: "A3")!)
styled.setFormat(CellFormat(numberFormat: "\"$\"#,##0.0"), at: CellAddress(a1: "B1")!)
styled.merges = [CellRange(CellAddress(a1: "D1")!, CellAddress(a1: "F2")!)]
styled.rowHeights = [0: 30]
styled.hiddenColumns = [7]
styled.columnWidths = [2: 100]
styled.conditionalFormats = [
    ConditionalFormat(ranges: [CellRange(CellAddress(a1: "A2")!, CellAddress(a1: "A3")!)], rule: .cellIs(.greaterThan, "1", nil, .lightRedFillDarkRedText)),
    ConditionalFormat(ranges: [CellRange(CellAddress(a1: "A4")!, CellAddress(a1: "A5")!)], rule: .text(.containsText, "x", .greenFillDarkGreenText)),
    ConditionalFormat(ranges: [CellRange(CellAddress(a1: "A2")!, CellAddress(a1: "A3")!)], rule: .dataBar(RGBColor(hex: "638EC6")!)),
    ConditionalFormat(ranges: [CellRange(CellAddress(a1: "A2")!, CellAddress(a1: "A3")!)], rule: .colorScale([
        ScaleStop(.min, color: RGBColor(hex: "F8696B")!), ScaleStop(.percentile, "50", color: RGBColor(hex: "FFEB84")!), ScaleStop(.max, color: RGBColor(hex: "63BE7B")!),
    ])),
    ConditionalFormat(ranges: [CellRange(CellAddress(a1: "A2")!, CellAddress(a1: "A5")!)], rule: .expression("MOD(ROW(),2)=0", DifferentialStyle(bold: true))),
]
styled.frozenRows = 1
styled.showGridlines = false
styled.hiddenRows = [7]
var filtered = sheet(["A1": "K", "A2": "x", "A3": "y", "A4": ""], name: "Filtered")
filtered.filter = AutoFilter(range: CellRange(CellAddress(a1: "A1")!, CellAddress(a1: "A4")!), allowedValues: [0: ["y", ""]])
let styledBook = Workbook(sheets: [styled, filtered])
check("decimals shown", display(styledBook, "A2"), "1,234.568")
check("percent 0dp", display(styledBook, "A3"), "50%")
check("currency 1dp", display(styledBook, "B1"), "$2,469.1")
do {
    let reread = try XLSXReader.workbook(from: XLSXWriter.data(for: styledBook))
    check("rich formats", reread.sheets[0].formats, styled.formats)
    check("frozen rows", reread.sheets[0].frozenRows, 1)
    check("gridlines", reread.sheets[0].showGridlines, false)
    check("manual hidden rows", reread.sheets[0].hiddenRows, [7])
    check("filter", reread.sheets[1].filter, filtered.filter)
    check("filter hidden rows", Calculator(workbook: reread).hiddenRows(sheet: 1), [1])
    check("merges", reread.sheets[0].merges, styled.merges)
    check("row heights", reread.sheets[0].rowHeights, [0: 30])
    check("hidden columns", reread.sheets[0].hiddenColumns, [7])
    check("conditional formats", reread.sheets[0].conditionalFormats, styled.conditionalFormats)
    let calc = Calculator(workbook: reread)
    check("cf cellIs", calc.conditionalFormatting(sheet: 0, at: CellAddress(a1: "A2")!)?.style.fillColor, RGBColor(hex: "FFC7CE"))
    check("cf cellIs miss", calc.conditionalFormatting(sheet: 0, at: CellAddress(a1: "A3")!)?.style.fillColor, nil)
    check("cf text", calc.conditionalFormatting(sheet: 0, at: CellAddress(a1: "A4")!)?.style.fillColor, RGBColor(hex: "C6EFCE"))
    check("cf expression row", calc.conditionalFormatting(sheet: 0, at: CellAddress(a1: "A4")!)?.style.bold, true)
    check("cf data bar", calc.conditionalFormatting(sheet: 0, at: CellAddress(a1: "A2")!)?.dataBar?.fraction, 1)
    check("cf color scale max", calc.conditionalFormatting(sheet: 0, at: CellAddress(a1: "A2")!)?.scaleColor, RGBColor(hex: "63BE7B"))
    check("cf color scale min", calc.conditionalFormatting(sheet: 0, at: CellAddress(a1: "A3")!)?.scaleColor, RGBColor(hex: "F8696B"))
} catch {
    failures += 1
    print("FAIL rich xlsx round trip: \(error)")
}
try? XLSXWriter.data(for: styledBook).write(to: FileManager.default.temporaryDirectory.appendingPathComponent("SheetCoreChecks-styled.xlsx"))

let xlsxPath = FileManager.default.temporaryDirectory.appendingPathComponent("SheetCoreChecks.xlsx")
try? xlsx.write(to: xlsxPath)

print("\(passed) passed, \(failures) failed. Sample workbook: \(xlsxPath.path)")
exit(failures == 0 ? 0 : 1)
