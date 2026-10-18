import Foundation

/// Argument access for one function call, shared by the extended function set.
struct FunctionArguments {
    let calculator: Calculator
    let args: [Expr]
    let sheet: Int

    var count: Int { args.count }

    func expect(_ counts: ClosedRange<Int>) throws {
        guard counts.contains(args.count) else { throw CellError.value }
    }

    /// The argument's value without failing on error values.
    func raw(_ i: Int) -> CellValue { calculator.scalar(args[i], sheet) }

    func value(_ i: Int) throws -> CellValue {
        let v = raw(i)
        if case .error(let e) = v { throw e }
        return v
    }

    func num(_ i: Int) throws -> Double { try Calculator.number(value(i)) }
    func str(_ i: Int) throws -> String { try Calculator.text(value(i)) }
    func bool(_ i: Int) throws -> Bool { try Calculator.boolean(value(i)) }

    func int(_ i: Int) throws -> Int {
        let n = try num(i)
        guard abs(n) < 1e9 else { throw CellError.number }
        return Int(n.rounded(.towardZero))
    }

    func range(_ i: Int) throws -> (sheet: Int, range: CellRange) {
        guard case .range(let s, let r) = calculator.evaluate(args[i], sheet) else { throw CellError.value }
        return (s, r)
    }

    func numbers(from start: Int) throws -> [Double] {
        try calculator.numbers(Array(args[start...]), sheet)
    }

    func finite(_ x: Double) throws -> CellValue {
        guard x.isFinite else { throw CellError.number }
        return .number(x)
    }

    func cell(_ target: (sheet: Int, range: CellRange), rows: Int, columns: Int) -> CellValue {
        calculator.value(sheet: target.sheet, at: target.range.start.offset(rows: rows, columns: columns))
    }

    /// Offsets (from each range's corner) where every range/criterion pair from `start` matches.
    func matchingOffsets(pairsFrom start: Int) throws -> [(rows: Int, columns: Int)] {
        var pairs: [(target: (sheet: Int, range: CellRange), criterion: Criterion)] = []
        for i in stride(from: start, to: count, by: 2) {
            pairs.append((try range(i), Criterion(raw(i + 1))))
        }
        guard let first = pairs.first?.target,
              pairs.allSatisfy({ $0.target.range.rowCount == first.range.rowCount && $0.target.range.columnCount == first.range.columnCount })
        else { throw CellError.value }
        return calculator.cells(in: first.range, sheet: first.sheet).compactMap { address, _ in
            let rows = address.row - first.range.start.row
            let columns = address.column - first.range.start.column
            let matches = pairs.allSatisfy { $0.criterion.matches(cell($0.target, rows: rows, columns: columns)) }
            return matches ? (rows, columns) : nil
        }
    }

    func callExtended(_ name: String) throws -> CellValue {
        switch name {
        case "SUMIFS", "AVERAGEIFS", "MAXIFS", "MINIFS":
            guard count >= 3, count % 2 == 1 else { throw CellError.value }
            let target = try range(0)
            let values = try matchingOffsets(pairsFrom: 1).compactMap { offset -> Double? in
                if case .number(let n) = cell(target, rows: offset.rows, columns: offset.columns) { return n }
                return nil
            }
            switch name {
            case "SUMIFS": return try finite(values.reduce(0, +))
            case "MAXIFS": return .number(values.max() ?? 0)
            case "MINIFS": return .number(values.min() ?? 0)
            default:
                guard !values.isEmpty else { throw CellError.divideByZero }
                return try finite(values.reduce(0, +) / Double(values.count))
            }
        case "COUNTIFS":
            guard count >= 2, count % 2 == 0 else { throw CellError.value }
            return .number(Double(try matchingOffsets(pairsFrom: 0).count))

        case "IFS":
            guard count >= 2, count % 2 == 0 else { throw CellError.value }
            for i in stride(from: 0, to: count, by: 2) {
                if try bool(i) { return raw(i + 1) }
            }
            throw CellError.notAvailable
        case "SWITCH":
            guard count >= 3 else { throw CellError.value }
            let subject = try value(0)
            var i = 1
            while i + 1 < count {
                let candidate = try value(i)
                if Calculator.rank(candidate) == Calculator.rank(subject), Calculator.compare(subject, candidate) == 0 { return raw(i + 1) }
                i += 2
            }
            if i == count - 1 { return raw(i) }
            throw CellError.notAvailable
        case "CHOOSE":
            guard count >= 2 else { throw CellError.value }
            let index = try int(0)
            guard (1..<count).contains(index) else { throw CellError.value }
            return raw(index)

        case "XLOOKUP":
            try expect(3...4)
            let lookup = try value(0)
            let keys = try range(1)
            let results = try range(2)
            let offset: Int
            do {
                offset = try calculator.lookupOffset(lookup, in: keys.range, sheet: keys.sheet, matchType: 0)
            } catch CellError.notAvailable where count == 4 {
                return raw(3)
            }
            let vertical = keys.range.columnCount == 1
            return cell(results, rows: vertical ? offset : 0, columns: vertical ? 0 : offset)
        case "HLOOKUP":
            try expect(3...4)
            let lookup = try value(0)
            let table = try range(1)
            let row = try int(2)
            let exact = count == 4 ? !(try bool(3)) : false
            guard row >= 1 else { throw CellError.value }
            guard row <= table.range.rowCount else { throw CellError.reference }
            let keys = CellRange(table.range.start, CellAddress(row: table.range.start.row, column: table.range.end.column))
            let column = try calculator.lookupOffset(lookup, in: keys, sheet: table.sheet, matchType: exact ? 0 : 1)
            return cell(table, rows: row - 1, columns: column)
        case "ROWS", "COLUMNS":
            try expect(1...1)
            let r = try range(0).range
            return .number(Double(name == "ROWS" ? r.rowCount : r.columnCount))
        case "ROW", "COLUMN":
            try expect(0...1)
            let address: CellAddress
            if count == 1 {
                address = try range(0).range.start
            } else {
                guard let current = calculator.currentCell else { throw CellError.value }
                address = current
            }
            return .number(Double((name == "ROW" ? address.row : address.column) + 1))

        case "TEXTJOIN":
            guard count >= 3 else { throw CellError.value }
            let delimiter = try str(0)
            let ignoreEmpty = try bool(1)
            var parts: [String] = []
            for (v, _) in calculator.flatten(Array(args[2...]), sheet) {
                let text = try Calculator.text(v)
                if !(ignoreEmpty && text.isEmpty) { parts.append(text) }
            }
            return .text(parts.joined(separator: delimiter))
        case "SUMPRODUCT":
            guard count >= 1 else { throw CellError.value }
            let ranges = try (0..<count).map { try range($0) }
            let first = ranges[0].range
            guard ranges.allSatisfy({ $0.range.rowCount == first.rowCount && $0.range.columnCount == first.columnCount }),
                  first.cellCount <= 1_000_000 else { throw CellError.value }
            var total = 0.0
            for r in 0..<first.rowCount {
                for c in 0..<first.columnCount {
                    total += ranges.reduce(1.0) { product, target in
                        if case .number(let n) = cell(target, rows: r, columns: c) { return product * n }
                        return 0
                    }
                }
            }
            return try finite(total)

        case "MEDIAN":
            let values = try numbers(from: 0).sorted()
            guard !values.isEmpty else { throw CellError.number }
            let middle = values.count / 2
            return .number(values.count % 2 == 1 ? values[middle] : (values[middle - 1] + values[middle]) / 2)
        case "STDEV", "STDEV.S", "STDEV.P", "VAR", "VAR.S", "VAR.P":
            let values = try numbers(from: 0)
            let population = name.hasSuffix(".P")
            guard values.count >= (population ? 1 : 2) else { throw CellError.divideByZero }
            let mean = values.reduce(0, +) / Double(values.count)
            let squares = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
            let variance = squares / Double(values.count - (population ? 0 : 1))
            return try finite(name.hasPrefix("STDEV") ? variance.squareRoot() : variance)
        case "LARGE", "SMALL":
            try expect(2...2)
            let values = try calculator.numbers([args[0]], sheet).sorted(by: name == "LARGE" ? (>) : (<))
            let k = try int(1)
            guard k >= 1, k <= values.count else { throw CellError.number }
            return .number(values[k - 1])
        case "RANK", "RANK.EQ":
            try expect(2...3)
            let x = try num(0)
            let values = try calculator.numbers([args[1]], sheet)
            let ascending = count == 3 ? try num(2) != 0 : false
            guard values.contains(x) else { throw CellError.notAvailable }
            return .number(Double(1 + values.filter { ascending ? $0 < x : $0 > x }.count))

        case "CEILING", "FLOOR":
            try expect(1...2)
            let x = try num(0)
            let significance = count == 2 ? try num(1) : 1
            guard significance != 0 else { return .number(0) }
            guard !(x > 0 && significance < 0) else { throw CellError.number }
            let steps = (x / significance).rounded(name == "CEILING" ? .up : .down)
            return try finite(steps * significance)
        case "SIGN":
            try expect(1...1)
            let x = try num(0)
            return .number(x > 0 ? 1 : (x < 0 ? -1 : 0))
        case "RAND":
            try expect(0...0)
            return .number(Double.random(in: 0..<1))
        case "RANDBETWEEN":
            try expect(2...2)
            let low = try num(0).rounded(.up)
            let high = try num(1).rounded(.down)
            guard low <= high, abs(low) < 1e15, abs(high) < 1e15 else { throw CellError.number }
            return .number(Double(Int64.random(in: Int64(low)...Int64(high))))

        case "DATE":
            try expect(3...3)
            var year = try int(0)
            if year < 1900 { year += 1900 }
            let serial = DateMath.serial(year: year, month: try int(1), day: try int(2))
            guard serial >= 1 else { throw CellError.number }
            return .number(serial)
        case "YEAR", "MONTH", "DAY":
            try expect(1...1)
            guard let date = DateMath.civil(serial: try num(0)) else { throw CellError.number }
            return .number(Double(name == "YEAR" ? date.year : (name == "MONTH" ? date.month : date.day)))
        case "WEEKDAY":
            try expect(1...2)
            let unixDays = Int(try num(0).rounded(.down)) - 25_569
            let type = count == 2 ? try int(1) : 1
            let mondayBased = ((unixDays + 3) % 7 + 7) % 7
            switch type {
            case 1: return .number(Double((mondayBased + 1) % 7 + 1))
            case 2: return .number(Double(mondayBased + 1))
            case 3: return .number(Double(mondayBased))
            default: throw CellError.number
            }
        case "DAYS":
            try expect(2...2)
            return .number(try num(0).rounded(.down) - num(1).rounded(.down))
        case "EDATE", "EOMONTH":
            try expect(2...2)
            guard let date = DateMath.civil(serial: try num(0)) else { throw CellError.number }
            let months = try int(1)
            let monthEnd = DateMath.serial(year: date.year, month: date.month + months + 1, day: 1) - 1
            if name == "EOMONTH" { return .number(monthEnd) }
            let lastDay = DateMath.civil(serial: monthEnd)?.day ?? 28
            return .number(DateMath.serial(year: date.year, month: date.month + months, day: min(date.day, lastDay)))

        case "TEXT":
            try expect(2...2)
            let v = try value(0)
            let code = try str(1)
            let number: Double?
            switch v {
            case .number(let n): number = n
            case .text(let s): number = CellInput.parseNumber(s)
            case .empty: number = 0
            case .boolean, .error: number = nil
            }
            guard let number else { return .text(try str(0)) }
            return .text(ExcelNumberFormat.format(.number(number), code: code).text)
        case "SUBSTITUTE":
            try expect(3...4)
            let text = try str(0)
            let old = try str(1)
            let new = try str(2)
            guard !old.isEmpty else { return .text(text) }
            guard count == 4 else { return .text(text.replacingOccurrences(of: old, with: new)) }
            let instance = try int(3)
            guard instance >= 1 else { throw CellError.value }
            var searchStart = text.startIndex
            var seen = 0
            while let found = text.range(of: old, range: searchStart..<text.endIndex) {
                seen += 1
                if seen == instance { return .text(text.replacingCharacters(in: found, with: new)) }
                searchStart = found.upperBound
            }
            return .text(text)
        case "REPLACE":
            try expect(4...4)
            let chars = Array(try str(0))
            let start = try int(1)
            let length = try int(2)
            guard start >= 1, length >= 0 else { throw CellError.value }
            let low = min(start - 1, chars.count)
            let high = min(low + length, chars.count)
            return .text(String(chars[..<low]) + (try str(3)) + String(chars[high...]))
        case "FIND", "SEARCH":
            try expect(2...3)
            let needle = try str(0)
            let haystack = Array(try str(1))
            let start = count == 3 ? try int(2) : 1
            guard start >= 1, start <= haystack.count + 1 else { throw CellError.value }
            let tail = String(haystack[(start - 1)...])
            if needle.isEmpty { return .number(Double(start)) }
            guard let found = tail.range(of: needle, options: name == "FIND" ? [] : [.caseInsensitive]) else {
                throw CellError.value
            }
            return .number(Double(tail.distance(from: tail.startIndex, to: found.lowerBound) + start))
        case "REPT":
            try expect(2...2)
            let text = try str(0)
            let times = try int(1)
            guard times >= 0, text.count * times <= 32_767 else { throw CellError.value }
            return .text(String(repeating: text, count: times))
        case "PROPER":
            try expect(1...1)
            var result = ""
            var previousIsLetter = false
            for c in try str(0) {
                result += previousIsLetter ? c.lowercased() : c.uppercased()
                previousIsLetter = c.isLetter
            }
            return .text(result)
        case "EXACT":
            try expect(2...2)
            return .boolean(try str(0) == str(1))
        case "CHAR":
            try expect(1...1)
            let code = try int(0)
            guard (1...255).contains(code), let scalar = UnicodeScalar(code) else { throw CellError.value }
            return .text(String(Character(scalar)))
        case "CODE":
            try expect(1...1)
            guard let scalar = try str(0).unicodeScalars.first else { throw CellError.value }
            return .number(Double(scalar.value))

        case "ISBLANK":
            try expect(1...1)
            return .boolean(raw(0) == .empty)
        case "ISNUMBER":
            try expect(1...1)
            return .boolean(raw(0).isNumber)
        case "ISTEXT":
            try expect(1...1)
            if case .text = raw(0) { return .boolean(true) }
            return .boolean(false)
        case "ISLOGICAL":
            try expect(1...1)
            if case .boolean = raw(0) { return .boolean(true) }
            return .boolean(false)
        case "ISERROR", "ISNA":
            try expect(1...1)
            if case .error(let e) = raw(0) { return .boolean(name == "ISERROR" || e == .notAvailable) }
            return .boolean(false)
        case "NA":
            try expect(0...0)
            throw CellError.notAvailable

        default:
            return try callMore(name)
        }
    }
}
