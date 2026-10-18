import Foundation

extension FunctionArguments {
    func callMore(_ name: String) throws -> CellValue {
        func unary(_ f: (Double) -> Double) throws -> CellValue {
            try expect(1...1)
            return try finite(f(try num(0)))
        }
        func optionalNum(_ i: Int, _ fallback: Double) throws -> Double { i < count ? try num(i) : fallback }

        switch name {
        case "SIN": return try unary(sin)
        case "COS": return try unary(cos)
        case "TAN": return try unary(tan)
        case "SINH": return try unary(sinh)
        case "COSH": return try unary(cosh)
        case "TANH": return try unary(tanh)
        case "ATAN": return try unary(atan)
        case "ASIN", "ACOS":
            try expect(1...1)
            let x = try num(0)
            guard (-1...1).contains(x) else { throw CellError.number }
            return .number(name == "ASIN" ? asin(x) : acos(x))
        case "ATAN2":
            try expect(2...2)
            let (x, y) = (try num(0), try num(1))
            guard x != 0 || y != 0 else { throw CellError.divideByZero }
            return .number(atan2(y, x))
        case "DEGREES": return try unary { $0 * 180 / .pi }
        case "RADIANS": return try unary { $0 * .pi / 180 }

        case "TRUNC":
            try expect(1...2)
            let factor = pow(10, try optionalNum(1, 0).rounded(.towardZero))
            return try finite((try num(0) * factor).rounded(.towardZero) / factor)
        case "MROUND":
            try expect(2...2)
            let (x, multiple) = (try num(0), try num(1))
            guard multiple != 0 else { return .number(0) }
            guard x == 0 || (x > 0) == (multiple > 0) else { throw CellError.number }
            return try finite((x / multiple).rounded(.toNearestOrAwayFromZero) * multiple)
        case "EVEN", "ODD":
            try expect(1...1)
            let x = try num(0)
            let magnitude = abs(x)
            var rounded = magnitude.rounded(.up)
            if name == "EVEN" {
                if rounded.truncatingRemainder(dividingBy: 2) != 0 { rounded += 1 }
            } else if rounded.truncatingRemainder(dividingBy: 2) == 0 {
                rounded += 1
            }
            return .number(x < 0 ? -rounded : rounded)
        case "FACT":
            try expect(1...1)
            let n = Int(try num(0).rounded(.down))
            guard n >= 0, n <= 170 else { throw CellError.number }
            return .number((0..<n).reduce(1.0) { $0 * Double($1 + 1) })
        case "LOG":
            try expect(1...2)
            let (x, base) = (try num(0), try optionalNum(1, 10))
            guard x > 0, base > 0, base != 1 else { throw CellError.number }
            return .number(log(x) / log(base))
        case "SUMSQ":
            return try finite(try numbers(from: 0).reduce(0) { $0 + $1 * $1 })
        case "QUOTIENT":
            try expect(2...2)
            let (n, d) = (try num(0), try num(1))
            guard d != 0 else { throw CellError.divideByZero }
            return .number((n / d).rounded(.towardZero))
        case "GCD", "LCM":
            let values = try numbers(from: 0).map { $0.rounded(.down) }
            guard !values.isEmpty, values.allSatisfy({ $0 >= 0 && $0 < 9e15 }) else { throw CellError.number }
            func gcd(_ a: Int64, _ b: Int64) -> Int64 { b == 0 ? a : gcd(b, a % b) }
            let integers = values.map { Int64($0) }
            if name == "GCD" { return .number(Double(integers.reduce(0, gcd))) }
            if integers.contains(0) { return .number(0) }
            let lcm = integers.reduce(Int64(1)) { a, b in
                let (product, overflow) = (a / gcd(a, b)).multipliedReportingOverflow(by: b)
                return overflow ? Int64.max : product
            }
            guard lcm != Int64.max else { throw CellError.number }
            return .number(Double(lcm))

        case "MODE", "MODE.SNGL":
            let values = try numbers(from: 0)
            var counts: [Double: Int] = [:]
            for v in values { counts[v, default: 0] += 1 }
            guard let best = values.max(by: { counts[$0]! < counts[$1]! }), counts[best]! > 1,
                  let first = values.first(where: { counts[$0] == counts[best] }) else { throw CellError.notAvailable }
            return .number(first)
        case "STDEVP", "VARP":
            let variance = try Self.variance(try numbers(from: 0), population: true)
            return .number(name == "STDEVP" ? variance.squareRoot() : variance)
        case "MAXA", "MINA", "AVERAGEA":
            var values: [Double] = []
            for (v, fromRange) in calculator.flatten(args, sheet) {
                switch v {
                case .number(let n): values.append(n)
                case .boolean(let b): values.append(b ? 1 : 0)
                case .text(let s): values.append(fromRange ? 0 : try Calculator.number(.text(s)))
                case .error(let e): throw e
                case .empty: break
                }
            }
            switch name {
            case "MAXA": return .number(values.max() ?? 0)
            case "MINA": return .number(values.min() ?? 0)
            default:
                guard !values.isEmpty else { throw CellError.divideByZero }
                return .number(values.reduce(0, +) / Double(values.count))
            }
        case "SUBTOTAL":
            return try subtotal()

        case "TIME":
            try expect(3...3)
            let seconds = try num(0).rounded(.towardZero) * 3600 + num(1).rounded(.towardZero) * 60 + num(2).rounded(.towardZero)
            guard seconds >= 0 else { throw CellError.number }
            return .number((seconds / 86_400).truncatingRemainder(dividingBy: 1))
        case "HOUR", "MINUTE", "SECOND":
            try expect(1...1)
            let x = try num(0)
            guard x >= 0 else { throw CellError.number }
            let seconds = Int(((x - x.rounded(.down)) * 86_400).rounded()) % 86_400
            let part = switch name {
            case "HOUR": seconds / 3600
            case "MINUTE": seconds % 3600 / 60
            default: seconds % 60
            }
            return .number(Double(part))
        case "WORKDAY":
            try expect(2...3)
            var day = Int(try num(0).rounded(.down))
            var remaining = Int(try num(1).rounded(.towardZero))
            let holidays = try holidaySet(2)
            let step = remaining < 0 ? -1 : 1
            while remaining != 0 {
                day += step
                if Self.isWorkday(day, holidays) { remaining -= step }
            }
            return .number(Double(day))
        case "NETWORKDAYS":
            try expect(2...3)
            let start = Int(try num(0).rounded(.down))
            let end = Int(try num(1).rounded(.down))
            let holidays = try holidaySet(2)
            guard abs(end - start) < 1_000_000 else { throw CellError.number }
            let days = (min(start, end)...max(start, end)).filter { Self.isWorkday($0, holidays) }.count
            return .number(Double(end < start ? -days : days))

        case "CLEAN":
            try expect(1...1)
            return .text(String(try str(0).unicodeScalars.filter { $0.value >= 32 }.map(Character.init)))
        case "T":
            try expect(1...1)
            if case .text(let s) = try value(0) { return .text(s) }
            return .text("")
        case "N":
            try expect(1...1)
            switch try value(0) {
            case .number(let n): return .number(n)
            case .boolean(let b): return .number(b ? 1 : 0)
            default: return .number(0)
            }
        case "ISODD", "ISEVEN":
            try expect(1...1)
            let isEven = Int64(try num(0).rounded(.towardZero)) % 2 == 0
            return .boolean(name == "ISEVEN" ? isEven : !isEven)
        case "ISNONTEXT":
            try expect(1...1)
            if case .text = raw(0) { return .boolean(false) }
            return .boolean(true)
        case "ISREF":
            try expect(1...1)
            if case .range = calculator.evaluate(args[0], sheet) { return .boolean(true) }
            return .boolean(false)
        case "HYPERLINK":
            try expect(1...2)
            return count == 2 ? try value(1) : .text(try str(0))

        case "LOOKUP":
            try expect(2...3)
            let lookup = try value(0)
            let keys = try range(1)
            let offset = try calculator.lookupOffset(lookup, in: keys.range, sheet: keys.sheet, matchType: 1)
            let results = count == 3 ? try range(2) : keys
            let vertical = results.range.columnCount == 1
            return cell(results, rows: vertical ? offset : 0, columns: vertical ? 0 : offset)
        case "XMATCH":
            try expect(2...3)
            let lookup = try value(0)
            let target = try range(1)
            let mode = count == 3 ? try int(2) : 0
            let vertical = target.range.columnCount == 1
            guard vertical || target.range.rowCount == 1 else { throw CellError.value }
            var best: (offset: Int, value: CellValue)?
            for (address, v) in calculator.cells(in: target.range, sheet: target.sheet) where Calculator.rank(v) == Calculator.rank(lookup) {
                let offset = vertical ? address.row - target.range.start.row : address.column - target.range.start.column
                let order = Calculator.compare(v, lookup)
                if order == 0 { return .number(Double(offset + 1)) }
                if mode == -1, order < 0, best.map({ Calculator.compare(v, $0.value) > 0 }) ?? true { best = (offset, v) }
                if mode == 1, order > 0, best.map({ Calculator.compare(v, $0.value) < 0 }) ?? true { best = (offset, v) }
            }
            guard let best else { throw CellError.notAvailable }
            return .number(Double(best.offset + 1))

        case "PMT", "FV", "PV":
            try expect(3...5)
            let (rate, periods, third) = (try num(0), try num(1), try num(2))
            let fourth = try optionalNum(3, 0)
            let type = try optionalNum(4, 0) != 0 ? 1.0 : 0.0
            if rate == 0 {
                switch name {
                case "PMT": return try finite(-(third + fourth) / periods)
                case "FV": return try finite(-(fourth + third * periods))
                default: return try finite(-(fourth + third * periods))
                }
            }
            let growth = pow(1 + rate, periods)
            switch name {
            case "PMT": return try finite(-(rate * (fourth + third * growth)) / ((1 + rate * type) * (growth - 1)))
            case "FV": return try finite(-(fourth * growth + third * (1 + rate * type) * (growth - 1) / rate))
            default: return try finite(-(fourth + third * (1 + rate * type) * (growth - 1) / rate) / growth)
            }
        case "NPER":
            try expect(3...5)
            let (rate, payment, present) = (try num(0), try num(1), try num(2))
            let future = try optionalNum(3, 0)
            let type = try optionalNum(4, 0) != 0 ? 1.0 : 0.0
            if rate == 0 {
                guard payment != 0 else { throw CellError.number }
                return try finite(-(present + future) / payment)
            }
            let adjusted = payment * (1 + rate * type)
            return try finite(log((adjusted - future * rate) / (adjusted + present * rate)) / log(1 + rate))
        case "NPV":
            guard count >= 2 else { throw CellError.value }
            let rate = try num(0)
            let flows = try numbers(from: 1)
            return try finite(flows.enumerated().reduce(0) { $0 + $1.element / pow(1 + rate, Double($1.offset + 1)) })
        case "IRR":
            try expect(1...2)
            let flows = try calculator.numbers([args[0]], sheet)
            guard flows.contains(where: { $0 > 0 }), flows.contains(where: { $0 < 0 }) else { throw CellError.number }
            return .number(try Self.solve(guess: try optionalNum(1, 0.1)) { rate in
                flows.enumerated().reduce(0) { $0 + $1.element / pow(1 + rate, Double($1.offset)) }
            })
        case "RATE":
            try expect(3...6)
            let (periods, payment, present) = (try num(0), try num(1), try num(2))
            let future = try optionalNum(3, 0)
            let type = try optionalNum(4, 0) != 0 ? 1.0 : 0.0
            return .number(try Self.solve(guess: try optionalNum(5, 0.1)) { rate in
                if abs(rate) < 1e-12 { return present + payment * periods + future }
                let growth = pow(1 + rate, periods)
                return present * growth + payment * (1 + rate * type) * (growth - 1) / rate + future
            })

        case "HEX2DEC", "BIN2DEC", "OCT2DEC":
            try expect(1...1)
            let radix = name.hasPrefix("HEX") ? 16 : (name.hasPrefix("BIN") ? 2 : 8)
            let digits = try str(0).trimmingCharacters(in: .whitespaces)
            guard digits.count <= 10, var value = Int64(digits.isEmpty ? "0" : digits, radix: radix) else { throw CellError.number }
            // Ten-digit values are two's complement negatives.
            let bits = Int64(radix == 16 ? 40 : (radix == 2 ? 10 : 30))
            if digits.count == 10, value >= (Int64(1) << (bits - 1)) { value -= Int64(1) << bits }
            return .number(Double(value))
        case "DEC2HEX", "DEC2BIN", "DEC2OCT":
            try expect(1...2)
            let radix = name.hasSuffix("HEX") ? 16 : (name.hasSuffix("BIN") ? 2 : 8)
            var value = Int64(try num(0).rounded(.towardZero))
            let bits = Int64(radix == 16 ? 40 : (radix == 2 ? 10 : 30))
            guard abs(value) < (Int64(1) << (bits - 1)) else { throw CellError.number }
            if value < 0 { value += Int64(1) << bits }
            var text = String(value, radix: radix).uppercased()
            if count == 2 {
                let places = try int(1)
                guard places >= text.count, places <= 10 else { throw CellError.number }
                text = String(repeating: "0", count: places - text.count) + text
            }
            return .text(text)

        default:
            throw CellError.name
        }
    }

    /// SUBTOTAL: rows hidden by a filter are skipped (and rows hidden by hand for codes 101–111),
    /// as are other SUBTOTAL results, so nested subtotals do not double count.
    private func subtotal() throws -> CellValue {
        guard count >= 2 else { throw CellError.value }
        let code = try int(0)
        let function = code % 100
        guard (1...11).contains(function), code < 112 else { throw CellError.value }
        var values: [CellValue] = []
        for i in 1..<count {
            let target = try range(i)
            let sheetModel = calculator.workbook.sheets[target.sheet]
            let hidden = calculator.hiddenRows(sheet: target.sheet)
            let excluded = code > 100 ? hidden : hidden.subtracting(sheetModel.hiddenRows)
            for (address, value) in calculator.cells(in: target.range, sheet: target.sheet) where !excluded.contains(address.row) {
                if let raw = sheetModel.cells[address], raw.uppercased().hasPrefix("=SUBTOTAL(") { continue }
                if case .error(let e) = value { throw e }
                values.append(value)
            }
        }
        let numbers = values.compactMap { value -> Double? in
            if case .number(let n) = value { return n }
            return nil
        }
        switch function {
        case 1:
            guard !numbers.isEmpty else { throw CellError.divideByZero }
            return .number(numbers.reduce(0, +) / Double(numbers.count))
        case 2: return .number(Double(numbers.count))
        case 3: return .number(Double(values.count))
        case 4: return .number(numbers.max() ?? 0)
        case 5: return .number(numbers.min() ?? 0)
        case 6: return try finite(numbers.reduce(1, *))
        case 7, 8: return .number(try Self.variance(numbers, population: function == 8).squareRoot())
        case 9: return try finite(numbers.reduce(0, +))
        default: return .number(try Self.variance(numbers, population: function == 11))
        }
    }

    private func holidaySet(_ index: Int) throws -> Set<Int> {
        guard index < count else { return [] }
        return Set(try calculator.numbers([args[index]], sheet).map { Int($0.rounded(.down)) })
    }

    private static func isWorkday(_ serial: Int, _ holidays: Set<Int>) -> Bool {
        let mondayBased = ((serial - 25_569 + 3) % 7 + 7) % 7
        return mondayBased < 5 && !holidays.contains(serial)
    }

    static func variance(_ values: [Double], population: Bool) throws -> Double {
        guard values.count >= (population ? 1 : 2) else { throw CellError.divideByZero }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - (population ? 0 : 1))
    }

    /// Newton's method with a numeric derivative, as Excel's IRR and RATE iterate.
    private static func solve(guess: Double, _ f: (Double) -> Double) throws -> Double {
        var x = guess
        for _ in 0..<100 {
            let y = f(x)
            if abs(y) < 1e-10 { return x }
            let h = max(1e-7, abs(x) * 1e-7)
            let slope = (f(x + h) - y) / h
            guard slope.isFinite, slope != 0 else { break }
            let next = x - y / slope
            guard next.isFinite, next > -1 else { break }
            if abs(next - x) < 1e-12 { return next }
            x = next
        }
        throw CellError.number
    }
}

extension Calculator {
    /// INDIRECT and OFFSET produce references rather than values.
    func referenceFunction(_ name: String, _ args: [Expr], _ sheet: Int) -> Operand {
        switch name {
        case "INDIRECT":
            guard (1...2).contains(args.count) else { return .value(.error(.value)) }
            if args.count == 2, (try? Calculator.boolean(scalar(args[1], sheet))) == false {
                // R1C1-style text is not supported.
                return .value(.error(.reference))
            }
            guard let text = try? Calculator.text(scalar(args[0], sheet)),
                  case .success(let expr) = FormulaParser.parse("=" + text) else { return .value(.error(.reference)) }
            switch expr {
            case .reference, .range: return evaluate(expr, sheet)
            default: return .value(.error(.reference))
            }
        default:
            guard (3...5).contains(args.count),
                  case .range(let target, let base) = evaluate(args[0], sheet) else { return .value(.error(.value)) }
            do {
                func integer(_ i: Int, _ fallback: Int) throws -> Int {
                    guard i < args.count else { return fallback }
                    return Int(try Calculator.number(scalar(args[i], sheet)).rounded(.towardZero))
                }
                let start = base.start.offset(rows: try integer(1, 0), columns: try integer(2, 0))
                let height = try integer(3, base.rowCount)
                let width = try integer(4, base.columnCount)
                let end = start.offset(rows: height - 1, columns: width - 1)
                guard height >= 1, width >= 1, start.isValid, end.isValid else { return .value(.error(.reference)) }
                return .range(sheet: target, CellRange(start, end))
            } catch let error as CellError {
                return .value(.error(error))
            } catch {
                return .value(.error(.value))
            }
        }
    }
}
