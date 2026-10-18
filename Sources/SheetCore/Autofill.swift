import Foundation

extension Workbook {
    /// Extends the pattern in `source` into `target`, like dragging the fill handle. `target` must start at
    /// `source` and grow it downward (same columns) or to the right (same rows).
    ///
    /// Numbers continue their step (a single date counts up by days), text ending in a number counts up,
    /// month and weekday names continue, formulas move their relative references, and anything else repeats.
    public mutating func autofill(sheet index: Int, source: CellRange, target: CellRange) {
        guard sheets.indices.contains(index), target.start == source.start else { return }
        let down: Bool
        if target.columnCount == source.columnCount, target.rowCount > source.rowCount {
            down = true
        } else if target.rowCount == source.rowCount, target.columnCount > source.columnCount {
            down = false
        } else {
            return
        }
        var sheet = sheets[index]
        let lines = down ? source.start.column...source.end.column : source.start.row...source.end.row
        let length = down ? source.rowCount : source.columnCount
        let total = down ? target.rowCount : target.columnCount

        for line in lines {
            func address(_ position: Int) -> CellAddress {
                down ? CellAddress(row: source.start.row + position, column: line) : CellAddress(row: line, column: source.start.column + position)
            }
            let inputs = (0..<length).map { sheet.cells[address($0)] ?? "" }
            let series = FillSeries(inputs, isDate: ExcelNumberFormat.isDate(sheet.formats[address(0)]?.numberFormat ?? "General"))
            for position in length..<total {
                let target = address(position)
                guard target.isValid else { continue }
                let origin = address(position % length)
                let shift = position - position % length
                let input = series.value(at: position) ?? {
                    let raw = inputs[position % length]
                    return CellInput.isFormula(raw)
                        ? FormulaText.shifted(raw, rows: down ? shift : 0, columns: down ? 0 : shift)
                        : raw
                }()
                sheet.setInput(input, at: target)
                sheet.setFormat(sheet.formats[origin] ?? CellFormat(), at: target)
                sheet.controls[target] = sheet.controls[origin]
            }
        }
        sheets[index] = sheet
    }
}

/// A recognised progression in one row or column of cells.
struct FillSeries {
    private enum Kind {
        case numbers(start: Double, step: Double)
        case numbered(prefix: String, start: Int, step: Int, width: Int)
        case names(list: [String], start: Int, step: Int, style: (String) -> String)
        case repeating
    }

    private let kind: Kind

    static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                         "October", "November", "December"]
    static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    init(_ inputs: [String], isDate: Bool) {
        let count = inputs.count
        let numbers = inputs.map { input -> Double? in
            guard !CellInput.isFormula(input), case .number(let n) = CellInput.literalValue(input) else { return nil }
            return n
        }
        if numbers.allSatisfy({ $0 != nil }) {
            let values = numbers.map { $0! }
            if count >= 2 {
                kind = .numbers(start: values[0], step: (values[count - 1] - values[0]) / Double(count - 1))
            } else {
                kind = isDate ? .numbers(start: values[0], step: 1) : .repeating
            }
            return
        }
        // Text ending in a number, such as "Item 1" or "Q01".
        let numbered = inputs.map { input -> (prefix: String, number: Int, width: Int)? in
            guard !CellInput.isFormula(input), case .text(let text) = CellInput.literalValue(input) else { return nil }
            let digits = text.reversed().prefix { $0.isASCII && $0.isNumber }
            guard !digits.isEmpty, digits.count <= 9, let number = Int(String(digits.reversed())) else { return nil }
            return (String(text.dropLast(digits.count)), number, digits.count)
        }
        if numbered.allSatisfy({ $0 != nil }), let first = numbered[0], numbered.allSatisfy({ $0!.prefix == first.prefix }) {
            let step = count >= 2 ? (numbered[count - 1]!.number - first.number) / (count - 1) : 1
            kind = .numbered(prefix: first.prefix, start: first.number, step: step == 0 ? 1 : step, width: first.width)
            return
        }
        // Month and weekday names, full or abbreviated.
        for list in [Self.months, Self.weekdays] {
            for abbreviated in [false, true] {
                let names = abbreviated ? list.map { String($0.prefix(3)) } : list
                let indexes = inputs.map { input in names.firstIndex { $0.caseInsensitiveCompare(input.trimmingCharacters(in: .whitespaces)) == .orderedSame } }
                guard indexes.allSatisfy({ $0 != nil }), let first = indexes[0], let sample = inputs.first else { continue }
                let step = count >= 2 ? (indexes[1]! - first) : 1
                let style: (String) -> String = sample == sample.uppercased() ? { $0.uppercased() }
                    : (sample == sample.lowercased() ? { $0.lowercased() } : { $0 })
                kind = .names(list: names, start: first, step: step == 0 ? 1 : step, style: style)
                return
            }
        }
        kind = .repeating
    }

    /// The input at a position in the extended line, or nil to repeat the source cells.
    func value(at position: Int) -> String? {
        switch kind {
        case .numbers(let start, let step):
            return CellInput.rawInput(for: .number(start + step * Double(position)))
        case .numbered(let prefix, let start, let step, let width):
            let number = start + step * position
            let digits = String(abs(number))
            let padded = String(repeating: "0", count: max(0, width - digits.count)) + digits
            return prefix + (number < 0 ? "-" : "") + padded
        case .names(let list, let start, let step, let style):
            let index = ((start + step * position) % list.count + list.count) % list.count
            return style(list[index])
        case .repeating:
            return nil
        }
    }
}
