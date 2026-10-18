import Foundation

/// Ready-made sheets to start from, in the spirit of Numbers' template gallery.
public enum SheetTemplate: String, CaseIterable, Identifiable, Sendable {
    case budget = "Personal Budget"
    case invoice = "Invoice"
    case checklist = "Checklist"
    case planner = "Weekly Planner"
    case gradeBook = "Grade Book"
    case readingList = "Reading List"

    public var id: String { rawValue }

    public var summary: String {
        switch self {
        case .budget: "Monthly income and spending by category, with differences."
        case .invoice: "Line items with quantities, subtotal, tax and total."
        case .checklist: "Tasks with checkboxes, priorities, due dates and progress."
        case .planner: "A week laid out in hourly slots."
        case .gradeBook: "Scores, averages and letter grades for a class."
        case .readingList: "Books with star ratings, genres and a read checkbox."
        }
    }

    public func makeSheet(named name: String) -> Sheet {
        var builder = TemplateBuilder(name: name)
        switch self {
        case .budget: builder.budget()
        case .invoice: builder.invoice()
        case .checklist: builder.checklist()
        case .planner: builder.planner()
        case .gradeBook: builder.gradeBook()
        case .readingList: builder.readingList()
        }
        return builder.sheet
    }
}

extension Workbook {
    /// Appends a sheet made from a template and returns its index.
    @discardableResult
    public mutating func addSheet(from template: SheetTemplate) -> Int {
        sheets.append(template.makeSheet(named: uniqueSheetName(template.rawValue)))
        return sheets.count - 1
    }
}

private struct TemplateBuilder {
    var sheet: Sheet

    init(name: String) {
        sheet = Sheet(name: name)
    }

    private static let accent = RGBColor(hex: "4472C4")
    private static let ink = RGBColor(hex: "44546A")
    private static let band = RGBColor(hex: "F2F6FC")
    private static let white = RGBColor(hex: "FFFFFF")
    private static let accounting = NumberFormatPreset.accounting.code

    private func at(_ a1: String) -> CellAddress { CellAddress(a1: a1)! }

    mutating func set(_ a1: String, _ raw: String, _ format: CellFormat? = nil) {
        sheet.cells[at(a1)] = raw
        if let format { sheet.setFormat(format, at: at(a1)) }
    }

    mutating func format(_ a1: String, _ change: (inout CellFormat) -> Void) {
        var current = sheet.formats[at(a1)] ?? CellFormat()
        change(&current)
        sheet.setFormat(current, at: at(a1))
    }

    mutating func title(_ text: String, subtitle: String, across columns: Int) {
        set("A1", text, CellFormat(fontSize: 20, bold: true, textColor: Self.ink, verticalAlignment: .center))
        sheet.rowHeights[0] = 34
        sheet.merges.append(CellRange(at("A1"), CellAddress(row: 0, column: columns - 1)))
        set("A2", subtitle, CellFormat(italic: true, textColor: RGBColor(hex: "7F7F7F")))
    }

    /// A header row in the accent color, with alternating bands below it.
    mutating func table(headerRow: Int, columns: Int, rows: Int) {
        for column in 0..<columns {
            let address = CellAddress(row: headerRow, column: column)
            var format = sheet.formats[address] ?? CellFormat()
            (format.bold, format.textColor, format.fillColor) = (true, Self.white, Self.accent)
            sheet.setFormat(format, at: address)
            for row in (headerRow + 1)..<(headerRow + 1 + rows) {
                let cell = CellAddress(row: row, column: column)
                var body = sheet.formats[cell] ?? CellFormat()
                if (row - headerRow) % 2 == 0 { body.fillColor = Self.band }
                body.border.bottom = BorderLine(.thin, color: RGBColor(hex: "D9E1F2"))
                sheet.setFormat(body, at: cell)
            }
        }
    }

    mutating func totals(row: Int, columns: Int) {
        for column in 0..<columns {
            let address = CellAddress(row: row, column: column)
            var format = sheet.formats[address] ?? CellFormat()
            format.bold = true
            format.border = CellBorder(top: BorderLine(.thin, color: Self.accent), bottom: BorderLine(.double, color: Self.accent))
            sheet.setFormat(format, at: address)
        }
    }

    mutating func budget() {
        title("Personal Budget", subtitle: "Enter what you planned and what you spent; differences update automatically.", across: 4)
        let headers = ["Category", "Budget", "Actual", "Difference"]
        for (i, header) in headers.enumerated() {
            set(CellAddress(row: 3, column: i).a1, header, CellFormat(alignment: i == 0 ? .general : .right))
        }
        let items: [(String, Int, Int)] = [("Housing", 1500, 1500), ("Groceries", 600, 640), ("Transport", 250, 210),
                                           ("Utilities", 200, 185), ("Health", 120, 90), ("Entertainment", 150, 205),
                                           ("Savings", 500, 500), ("Other", 100, 60)]
        for (i, item) in items.enumerated() {
            let row = 5 + i
            set("A\(row)", item.0)
            set("B\(row)", String(item.1), CellFormat(numberFormat: Self.accounting))
            set("C\(row)", String(item.2), CellFormat(numberFormat: Self.accounting))
            set("D\(row)", "=B\(row)-C\(row)", CellFormat(numberFormat: Self.accounting))
        }
        table(headerRow: 3, columns: 4, rows: items.count)
        let total = 5 + items.count
        set("A\(total)", "Total")
        for column in ["B", "C", "D"] { set("\(column)\(total)", "=SUM(\(column)5:\(column)\(total - 1))", CellFormat(numberFormat: Self.accounting)) }
        totals(row: total - 1, columns: 4)
        sheet.conditionalFormats = [
            ConditionalFormat(ranges: [CellRange(at("D5"), at("D\(total - 1)"))], rule: .cellIs(.lessThan, "0", nil, .lightRedFillDarkRedText)),
            ConditionalFormat(ranges: [CellRange(at("C5"), at("C\(total - 1)"))], rule: .dataBar(RGBColor(hex: "638EC6")!)),
        ]
        sheet.columnWidths = [0: 150, 1: 110, 2: 110, 3: 110]
        sheet.frozenRows = 4
    }

    mutating func invoice() {
        title("Invoice", subtitle: "[Your Company] · [Street, City] · [Email]", across: 4)
        set("A4", "Bill to", CellFormat(bold: true))
        set("A5", "[Client name]")
        set("A6", "[Client address]")
        set("C4", "Invoice #", CellFormat(bold: true, alignment: .right))
        set("D4", "0001", CellFormat(alignment: .right))
        sheet.cells[at("D4")] = "'0001"
        set("C5", "Date", CellFormat(bold: true, alignment: .right))
        set("D5", "=TODAY()", CellFormat(numberFormat: "mmmm d, yyyy"))
        set("C6", "Due", CellFormat(bold: true, alignment: .right))
        set("D6", "=D5+30", CellFormat(numberFormat: "mmmm d, yyyy"))

        let headers = ["Description", "Quantity", "Unit Price", "Amount"]
        for (i, header) in headers.enumerated() { set(CellAddress(row: 7, column: i).a1, header, CellFormat(alignment: i == 0 ? .general : .right)) }
        let lines: [(String, Int, Double)] = [("Design consultation", 2, 150), ("Website build", 1, 1800), ("Hosting (12 months)", 1, 240),
                                              ("", 0, 0), ("", 0, 0)]
        for (i, line) in lines.enumerated() {
            let row = 9 + i
            if !line.0.isEmpty {
                set("A\(row)", line.0)
                set("B\(row)", String(line.1))
                set("C\(row)", CellValue.number(line.2).displayText)
            }
            sheet.controls[at("B\(row)")] = .stepper(minimum: 0, maximum: 999, step: 1)
            format("C\(row)") { $0.numberFormat = Self.accounting }
            set("D\(row)", "=B\(row)*C\(row)", CellFormat(numberFormat: Self.accounting))
        }
        table(headerRow: 7, columns: 4, rows: lines.count)
        let subtotal = 9 + lines.count
        set("C\(subtotal)", "Subtotal", CellFormat(bold: true, alignment: .right))
        set("D\(subtotal)", "=SUM(D9:D\(subtotal - 1))", CellFormat(numberFormat: Self.accounting))
        set("B\(subtotal + 1)", "8%", CellFormat(numberFormat: "0%"))
        set("C\(subtotal + 1)", "Tax", CellFormat(bold: true, alignment: .right))
        set("D\(subtotal + 1)", "=D\(subtotal)*B\(subtotal + 1)", CellFormat(numberFormat: Self.accounting))
        set("C\(subtotal + 2)", "Total due", CellFormat(fontSize: 13, bold: true, alignment: .right))
        set("D\(subtotal + 2)", "=D\(subtotal)+D\(subtotal + 1)", CellFormat(fontSize: 13, bold: true, numberFormat: Self.accounting))
        format("D\(subtotal + 2)") { $0.border = CellBorder(top: BorderLine(.thin, color: Self.accent), bottom: BorderLine(.double, color: Self.accent)) }
        set("A\(subtotal + 4)", "Thank you for your business. Payment is due within 30 days.", CellFormat(italic: true, textColor: Self.ink))
        sheet.columnWidths = [0: 220, 1: 80, 2: 110, 3: 120]
    }

    mutating func checklist() {
        title("Checklist", subtitle: "Tick tasks off as you go; finished tasks fade and progress updates.", across: 4)
        set("A3", "Progress", CellFormat(bold: true))
        set("B3", "=IFERROR(COUNTIF(A6:A20,TRUE)/COUNTA(B6:B20),0)", CellFormat(bold: true, numberFormat: "0%"))
        let headers = ["Done", "Task", "Priority", "Due"]
        for (i, header) in headers.enumerated() { set(CellAddress(row: 4, column: i).a1, header, CellFormat(alignment: i == 0 ? .center : .general)) }
        let tasks: [(Bool, String, String, Int)] = [(true, "Book flights", "High", 0), (false, "Renew passport", "High", 3),
                                                    (false, "Plan itinerary", "Medium", 7), (false, "Pack bags", "Low", 12),
                                                    (false, "Arrange pet sitter", "Medium", 10)]
        for row in 6...20 {
            sheet.controls[at("A\(row)")] = .checkbox
            sheet.controls[at("C\(row)")] = .popUp(.items(["High", "Medium", "Low"]))
            set("A\(row)", "FALSE", CellFormat(alignment: .center))
            format("D\(row)") { $0.numberFormat = "mmm d" }
        }
        for (i, task) in tasks.enumerated() {
            let row = 6 + i
            set("A\(row)", task.0 ? "TRUE" : "FALSE")
            set("B\(row)", task.1)
            set("C\(row)", task.2)
            set("D\(row)", "=TODAY()+\(task.3)")
        }
        table(headerRow: 4, columns: 4, rows: 15)
        sheet.conditionalFormats = [
            ConditionalFormat(ranges: [CellRange(at("B6"), at("D20"))],
                              rule: .expression("$A6=TRUE", DifferentialStyle(strikethrough: true, textColor: RGBColor(hex: "A6A6A6")))),
            ConditionalFormat(ranges: [CellRange(at("C6"), at("C20"))], rule: .cellIs(.equal, "\"High\"", nil, .lightRedFillDarkRedText)),
        ]
        sheet.columnWidths = [0: 50, 1: 220, 2: 90, 3: 80]
        sheet.frozenRows = 5
    }

    mutating func planner() {
        title("Weekly Planner", subtitle: "One row per hour from 8 AM to 6 PM.", across: 8)
        let days = ["Time", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        for (i, day) in days.enumerated() { set(CellAddress(row: 3, column: i).a1, day, CellFormat(alignment: .center)) }
        for (offset, hour) in (8...18).enumerated() {
            let row = 5 + offset
            set("A\(row)", CellInput.rawInput(for: .number(Double(hour) / 24)), CellFormat(textColor: Self.ink, numberFormat: "h AM/PM"))
            for column in 1...7 {
                sheet.setFormat(CellFormat(verticalAlignment: .top, wrapText: true), at: CellAddress(row: row - 1, column: column))
            }
            sheet.rowHeights[row - 1] = 30
        }
        set("B6", "Team meeting")
        set("D9", "Lunch with Sam")
        set("F7", "Gym")
        table(headerRow: 3, columns: 8, rows: 11)
        sheet.columnWidths = [0: 70, 1: 110, 2: 110, 3: 110, 4: 110, 5: 110, 6: 110, 7: 110]
        sheet.frozenRows = 4
    }

    mutating func gradeBook() {
        title("Grade Book", subtitle: "Averages and letter grades update as you enter scores.", across: 6)
        let headers = ["Student", "Test 1", "Test 2", "Test 3", "Average", "Grade"]
        for (i, header) in headers.enumerated() { set(CellAddress(row: 3, column: i).a1, header, CellFormat(alignment: i == 0 ? .general : .center)) }
        let students: [(String, [Int])] = [("Avery", [88, 92, 95]), ("Blake", [72, 68, 80]), ("Casey", [95, 98, 91]),
                                           ("Devon", [61, 75, 70]), ("Emery", [83, 79, 88]), ("Finley", [90, 85, 94])]
        for (i, student) in students.enumerated() {
            let row = 5 + i
            set("A\(row)", student.0)
            for (n, score) in student.1.enumerated() {
                set(CellAddress(row: row - 1, column: 1 + n).a1, String(score), CellFormat(alignment: .center))
            }
            set("E\(row)", "=AVERAGE(B\(row):D\(row))", CellFormat(alignment: .center, numberFormat: "0.0"))
            set("F\(row)", "=IFS(E\(row)>=90,\"A\",E\(row)>=80,\"B\",E\(row)>=70,\"C\",E\(row)>=60,\"D\",TRUE,\"F\")",
                CellFormat(bold: true, alignment: .center))
        }
        table(headerRow: 3, columns: 6, rows: students.count)
        let average = 5 + students.count
        set("A\(average)", "Class average")
        for column in ["B", "C", "D", "E"] {
            set("\(column)\(average)", "=AVERAGE(\(column)5:\(column)\(average - 1))", CellFormat(alignment: .center, numberFormat: "0.0"))
        }
        totals(row: average - 1, columns: 6)
        sheet.conditionalFormats = [
            ConditionalFormat(ranges: [CellRange(at("E5"), at("E\(average - 1)"))], rule: .colorScale([
                ScaleStop(.min, color: RGBColor(hex: "F8696B")!), ScaleStop(.percentile, "50", color: RGBColor(hex: "FFEB84")!),
                ScaleStop(.max, color: RGBColor(hex: "63BE7B")!),
            ])),
        ]
        sheet.columnWidths = [0: 130]
        sheet.frozenRows = 4
    }

    mutating func readingList() {
        title("Reading List", subtitle: "Rate books with stars, pick a genre and tick off what you have read.", across: 5)
        let headers = ["Title", "Author", "Genre", "Rating", "Read"]
        for (i, header) in headers.enumerated() { set(CellAddress(row: 3, column: i).a1, header, CellFormat(alignment: i >= 3 ? .center : .general)) }
        let books: [(String, String, String, Int, Bool)] = [
            ("Project Hail Mary", "Andy Weir", "Science Fiction", 5, true),
            ("The Thursday Murder Club", "Richard Osman", "Mystery", 4, true),
            ("Educated", "Tara Westover", "Memoir", 5, true),
            ("Piranesi", "Susanna Clarke", "Fantasy", 0, false),
            ("Sapiens", "Yuval Noah Harari", "History", 0, false),
        ]
        let genres = ["Fantasy", "History", "Memoir", "Mystery", "Romance", "Science Fiction", "Thriller"]
        for row in 5...24 {
            sheet.controls[at("C\(row)")] = .popUp(.items(genres))
            sheet.controls[at("D\(row)")] = .rating
            sheet.controls[at("E\(row)")] = .checkbox
            set("D\(row)", "0")
            set("E\(row)", "FALSE", CellFormat(alignment: .center))
        }
        for (i, book) in books.enumerated() {
            let row = 5 + i
            set("A\(row)", book.0)
            set("B\(row)", book.1)
            set("C\(row)", book.2)
            set("D\(row)", String(book.3))
            set("E\(row)", book.4 ? "TRUE" : "FALSE")
        }
        table(headerRow: 3, columns: 5, rows: 20)
        set("G4", "Books read", CellFormat(bold: true))
        set("H4", "=COUNTIF(E5:E24,TRUE)")
        set("G5", "Average rating", CellFormat(bold: true))
        set("H5", "=IFERROR(AVERAGEIF(D5:D24,\">0\"),0)", CellFormat(numberFormat: "0.0"))
        sheet.columnWidths = [0: 200, 1: 150, 2: 120, 3: 100, 4: 50, 6: 110]
        sheet.frozenRows = 4
    }
}
