import Foundation

extension Calculator {
    func call(_ name: String, _ args: [Expr], _ sheet: Int) -> CellValue {
        do {
            return try callThrowing(name, args, sheet)
        } catch let error as CellError {
            return .error(error)
        } catch {
            return .error(.value)
        }
    }

    private func callThrowing(_ name: String, _ args: [Expr], _ sheet: Int) throws -> CellValue {
        func expect(_ counts: ClosedRange<Int>) throws {
            guard counts.contains(args.count) else { throw CellError.value }
        }
        func value(_ i: Int) throws -> CellValue {
            let v = scalar(args[i], sheet)
            if case .error(let e) = v { throw e }
            return v
        }
        func num(_ i: Int) throws -> Double { try Calculator.number(value(i)) }
        func int(_ i: Int) throws -> Int {
            let n = try num(i)
            guard abs(n) < 1e9 else { throw CellError.number }
            return Int(n.rounded(.towardZero))
        }
        func str(_ i: Int) throws -> String { try Calculator.text(value(i)) }
        func range(_ i: Int) throws -> (sheet: Int, range: CellRange) {
            guard case .range(let s, let r) = evaluate(args[i], sheet) else { throw CellError.value }
            return (s, r)
        }
        func finite(_ x: Double) throws -> CellValue {
            guard x.isFinite else { throw CellError.number }
            return .number(x)
        }

        switch name {
        case "SUM":
            return try finite(numbers(args, sheet).reduce(0, +))
        case "PRODUCT":
            return try finite(numbers(args, sheet).reduce(1, *))
        case "AVERAGE":
            let values = try numbers(args, sheet)
            guard !values.isEmpty else { throw CellError.divideByZero }
            return try finite(values.reduce(0, +) / Double(values.count))
        case "MIN":
            return .number(try numbers(args, sheet).min() ?? 0)
        case "MAX":
            return .number(try numbers(args, sheet).max() ?? 0)
        case "COUNT":
            let counted = flatten(args, sheet).filter { value, fromRange in
                fromRange ? value.isNumber : (try? Calculator.number(value)) != nil
            }
            return .number(Double(counted.count))
        case "COUNTA":
            return .number(Double(flatten(args, sheet).filter { $0.value != .empty }.count))
        case "COUNTBLANK":
            try expect(1...1)
            let (s, r) = try range(0)
            return .number(Double(r.cellCount - cells(in: r, sheet: s).count))

        case "IF":
            try expect(2...3)
            if try Calculator.boolean(value(0)) { return scalar(args[1], sheet) }
            return args.count == 3 ? scalar(args[2], sheet) : .boolean(false)
        case "IFERROR":
            try expect(2...2)
            let v = scalar(args[0], sheet)
            if case .error = v { return scalar(args[1], sheet) }
            return v
        case "AND", "OR":
            let values = try logicalValues(args, sheet)
            guard !values.isEmpty else { throw CellError.value }
            return .boolean(name == "AND" ? values.allSatisfy { $0 } : values.contains(true))
        case "NOT":
            try expect(1...1)
            return .boolean(!(try Calculator.boolean(value(0))))
        case "TRUE", "FALSE":
            try expect(0...0)
            return .boolean(name == "TRUE")

        case "ABS":
            try expect(1...1)
            return .number(abs(try num(0)))
        case "SQRT":
            try expect(1...1)
            let x = try num(0)
            guard x >= 0 else { throw CellError.number }
            return .number(x.squareRoot())
        case "INT":
            try expect(1...1)
            return .number(try num(0).rounded(.down))
        case "EXP":
            try expect(1...1)
            return try finite(exp(try num(0)))
        case "LN", "LOG10":
            try expect(1...1)
            let x = try num(0)
            guard x > 0 else { throw CellError.number }
            return .number(name == "LN" ? log(x) : log10(x))
        case "ROUND", "ROUNDUP", "ROUNDDOWN":
            try expect(1...2)
            let x = try num(0)
            let digits = args.count == 2 ? try int(1) : 0
            guard abs(digits) <= 15 else { return .number(x) }
            let factor = pow(10, Double(digits))
            // Drop binary noise first so ROUND(2.675, 2) gives 2.68, as in Excel.
            let scaled = Double(String(format: "%.15g", x * factor)) ?? x * factor
            let rule: FloatingPointRoundingRule = switch name {
            case "ROUNDUP": .awayFromZero
            case "ROUNDDOWN": .towardZero
            default: .toNearestOrAwayFromZero
            }
            return try finite(scaled.rounded(rule) / factor)
        case "MOD":
            try expect(2...2)
            let (n, d) = (try num(0), try num(1))
            guard d != 0 else { throw CellError.divideByZero }
            return try finite(n - d * (n / d).rounded(.down))
        case "POWER":
            try expect(2...2)
            return try finite(pow(try num(0), try num(1)))
        case "PI":
            try expect(0...0)
            return .number(Double.pi)

        case "LEN":
            try expect(1...1)
            return .number(Double(try str(0).count))
        case "UPPER":
            try expect(1...1)
            return .text(try str(0).uppercased())
        case "LOWER":
            try expect(1...1)
            return .text(try str(0).lowercased())
        case "TRIM":
            try expect(1...1)
            return .text(try str(0).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " "))
        case "LEFT", "RIGHT":
            try expect(1...2)
            let text = try str(0)
            let count = args.count == 2 ? try int(1) : 1
            guard count >= 0 else { throw CellError.value }
            return .text(String(name == "LEFT" ? text.prefix(count) : text.suffix(count)))
        case "MID":
            try expect(3...3)
            let text = try str(0)
            let (start, count) = (try int(1), try int(2))
            guard start >= 1, count >= 0 else { throw CellError.value }
            return .text(String(text.dropFirst(start - 1).prefix(count)))
        case "CONCAT", "CONCATENATE":
            var result = ""
            for (v, _) in flatten(args, sheet) { result += try Calculator.text(v) }
            return .text(result)
        case "VALUE":
            try expect(1...1)
            return .number(try num(0))

        case "COUNTIF":
            try expect(2...2)
            let (s, r) = try range(0)
            let criterion = Criterion(scalar(args[1], sheet))
            return .number(Double(cells(in: r, sheet: s).filter { criterion.matches($0.value) }.count))
        case "SUMIF", "AVERAGEIF":
            try expect(2...3)
            let (s, r) = try range(0)
            let criterion = Criterion(scalar(args[1], sheet))
            let target = args.count == 3 ? try range(2) : (sheet: s, range: r)
            var matched: [Double] = []
            for (address, v) in cells(in: r, sheet: s) where criterion.matches(v) {
                let cell = target.range.start.offset(rows: address.row - r.start.row, columns: address.column - r.start.column)
                if case .number(let n) = self.value(sheet: target.sheet, at: cell) { matched.append(n) }
            }
            if name == "SUMIF" { return try finite(matched.reduce(0, +)) }
            guard !matched.isEmpty else { throw CellError.divideByZero }
            return try finite(matched.reduce(0, +) / Double(matched.count))

        case "VLOOKUP":
            try expect(3...4)
            let lookup = try value(0)
            let (s, table) = try range(1)
            let column = try int(2)
            let exact = args.count == 4 ? !(try Calculator.boolean(value(3))) : false
            guard column >= 1 else { throw CellError.value }
            guard column <= table.columnCount else { throw CellError.reference }
            let keys = CellRange(table.start, CellAddress(row: table.end.row, column: table.start.column))
            let row = try lookupOffset(lookup, in: keys, sheet: s, matchType: exact ? 0 : 1)
            return self.value(sheet: s, at: table.start.offset(rows: row, columns: column - 1))
        case "MATCH":
            try expect(2...3)
            let lookup = try value(0)
            let (s, r) = try range(1)
            let matchType = args.count == 3 ? try int(2) : 1
            return .number(Double(try lookupOffset(lookup, in: r, sheet: s, matchType: matchType.signum()) + 1))
        case "INDEX":
            try expect(2...3)
            let (s, r) = try range(0)
            var row = try int(1)
            var column = args.count == 3 ? try int(2) : 1
            if args.count == 2 && r.rowCount == 1 { (row, column) = (1, row) }
            // Row or column 0 returns a whole row/column array in Excel, which needs array formulas.
            guard row >= 1, column >= 1 else { throw CellError.value }
            guard row <= r.rowCount, column <= r.columnCount else { throw CellError.reference }
            return self.value(sheet: s, at: r.start.offset(rows: row - 1, columns: column - 1))

        case "TODAY", "NOW":
            try expect(0...0)
            let now = Date()
            let local = now.timeIntervalSince1970 + Double(TimeZone.current.secondsFromGMT(for: now))
            let serial = local / 86_400 + 25_569
            return .number(name == "TODAY" ? serial.rounded(.down) : serial)

        default:
            return try FunctionArguments(calculator: self, args: args, sheet: sheet).callExtended(name)
        }
    }

    /// Argument values with whether each came from a referenced range.
    func flatten(_ args: [Expr], _ sheet: Int) -> [(value: CellValue, fromRange: Bool)] {
        args.flatMap { arg -> [(value: CellValue, fromRange: Bool)] in
            switch evaluate(arg, sheet) {
            case .value(let v): return [(v, false)]
            case .range(let s, let r): return cells(in: r, sheet: s).map { ($0.value, true) }
            case .values(let values): return values.map { ($0, true) }
            case .areas(let areas): return areas.flatMap { area in cells(in: area.range, sheet: area.sheet).map { ($0.value, true) } }
            }
        }
    }

    /// Numbers for aggregate functions: referenced text and booleans are skipped,
    /// typed arguments are converted, and errors propagate.
    func numbers(_ args: [Expr], _ sheet: Int) throws -> [Double] {
        try flatten(args, sheet).compactMap { value, fromRange in
            if case .error(let e) = value { throw e }
            if fromRange {
                if case .number(let n) = value { return n }
                return nil
            }
            return try Calculator.number(value)
        }
    }

    func logicalValues(_ args: [Expr], _ sheet: Int) throws -> [Bool] {
        try flatten(args, sheet).compactMap { value, fromRange in
            if case .error(let e) = value { throw e }
            if fromRange {
                switch value {
                case .number(let n): return n != 0
                case .boolean(let b): return b
                default: return nil
                }
            }
            return try Calculator.boolean(value)
        }
    }

    /// Zero-based position of a value in a one-row or one-column range.
    /// Match type 0 is exact; 1 finds the largest value <= target in ascending data;
    /// -1 finds the smallest value >= target in descending data.
    func lookupOffset(_ target: CellValue, in range: CellRange, sheet: Int, matchType: Int) throws -> Int {
        let vertical = range.columnCount == 1
        guard vertical || range.rowCount == 1 else { throw CellError.notAvailable }
        var best: Int?
        scan: for (address, v) in cells(in: range, sheet: sheet) {
            let offset = vertical ? address.row - range.start.row : address.column - range.start.column
            guard Calculator.rank(v) == Calculator.rank(target) else { continue }
            let order = Calculator.compare(v, target)
            switch matchType {
            case 0:
                if order == 0 { return offset }
            case 1:
                guard order <= 0 else { break scan }
                best = offset
            default:
                guard order >= 0 else { break scan }
                best = offset
            }
        }
        guard let best else { throw CellError.notAvailable }
        return best
    }
}

/// A COUNTIF/SUMIF criterion such as `">5"`, `"<>done"` or `"app*"`.
struct Criterion {
    enum Comparison { case equal, notEqual, less, lessOrEqual, greater, greaterOrEqual }

    let comparison: Comparison
    let operand: CellValue

    init(_ value: CellValue) {
        guard case .text(let text) = value else {
            comparison = .equal
            operand = value
            return
        }
        let prefixes: [(String, Comparison)] = [
            ("<>", .notEqual), ("<=", .lessOrEqual), (">=", .greaterOrEqual), ("<", .less), (">", .greater), ("=", .equal),
        ]
        var comparison = Comparison.equal
        var rest = text
        if let (prefix, found) = prefixes.first(where: { text.hasPrefix($0.0) }) {
            comparison = found
            rest = String(text.dropFirst(prefix.count))
        }
        self.comparison = comparison
        let literal = CellInput.literalValue(rest)
        operand = literal == .empty ? .text("") : literal
    }

    func matches(_ cell: CellValue) -> Bool {
        if case .error = cell { return false }
        switch comparison {
        case .equal: return equals(cell)
        case .notEqual: return !equals(cell)
        default:
            let order: Int
            switch (cell, operand) {
            case (.number, .number), (.text, .text): order = Calculator.compare(cell, operand)
            default: return false
            }
            switch comparison {
            case .less: return order < 0
            case .lessOrEqual: return order <= 0
            case .greater: return order > 0
            default: return order >= 0
            }
        }
    }

    private func equals(_ cell: CellValue) -> Bool {
        switch (operand, cell) {
        case (.text(let pattern), .text(let text)): return Wildcard.matches(pattern, text)
        case (.text(let pattern), .empty): return pattern.isEmpty
        case (.number(let n), .number(let m)): return n == m
        case (.number(let n), .text(let text)): return CellInput.parseNumber(text) == n
        case (.boolean(let a), .boolean(let b)): return a == b
        default: return false
        }
    }
}

/// Excel wildcard matching: `*` any run, `?` one character, `~` escapes; case-insensitive.
enum Wildcard {
    private enum Piece: Equatable { case any, one, literal(Character) }

    static func matches(_ pattern: String, _ text: String) -> Bool {
        let p = Array(pattern.lowercased())
        let t = Array(text.lowercased())
        var pieces: [Piece] = []
        var i = 0
        while i < p.count {
            switch p[i] {
            case "~" where i + 1 < p.count: pieces.append(.literal(p[i + 1])); i += 1
            case "*": pieces.append(.any)
            case "?": pieces.append(.one)
            default: pieces.append(.literal(p[i]))
            }
            i += 1
        }
        var (pi, ti, star, mark) = (0, 0, -1, 0)
        while ti < t.count {
            if pi < pieces.count, pieces[pi] == .one || pieces[pi] == .literal(t[ti]) {
                pi += 1
                ti += 1
            } else if pi < pieces.count, pieces[pi] == .any {
                star = pi
                mark = ti
                pi += 1
            } else if star >= 0 {
                pi = star + 1
                mark += 1
                ti = mark
            } else {
                return false
            }
        }
        while pi < pieces.count, pieces[pi] == .any { pi += 1 }
        return pi == pieces.count
    }
}
