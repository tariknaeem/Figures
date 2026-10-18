import Foundation

/// The style a conditional rule applies; nil properties leave the cell's own format.
public struct DifferentialStyle: Hashable, Sendable {
    public var bold: Bool?
    public var italic: Bool?
    public var underline: Bool?
    public var strikethrough: Bool?
    public var textColor: RGBColor?
    public var fillColor: RGBColor?

    public init(bold: Bool? = nil, italic: Bool? = nil, underline: Bool? = nil, strikethrough: Bool? = nil,
                textColor: RGBColor? = nil, fillColor: RGBColor? = nil) {
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.textColor = textColor
        self.fillColor = fillColor
    }

    /// Fills properties this style leaves unset from a lower-priority style.
    mutating func merge(lowerPriority other: DifferentialStyle) {
        bold = bold ?? other.bold
        italic = italic ?? other.italic
        underline = underline ?? other.underline
        strikethrough = strikethrough ?? other.strikethrough
        textColor = textColor ?? other.textColor
        fillColor = fillColor ?? other.fillColor
    }

    public var isEmpty: Bool { self == DifferentialStyle() }

    /// Excel's built-in highlight styles.
    public static let lightRedFillDarkRedText = DifferentialStyle(textColor: RGBColor(hex: "9C0006"), fillColor: RGBColor(hex: "FFC7CE"))
    public static let yellowFillDarkYellowText = DifferentialStyle(textColor: RGBColor(hex: "9C5700"), fillColor: RGBColor(hex: "FFEB9C"))
    public static let greenFillDarkGreenText = DifferentialStyle(textColor: RGBColor(hex: "006100"), fillColor: RGBColor(hex: "C6EFCE"))
    public static let lightRedFill = DifferentialStyle(fillColor: RGBColor(hex: "FFC7CE"))
    public static let redText = DifferentialStyle(textColor: RGBColor(hex: "9C0006"))
}

public enum ComparisonOperator: String, CaseIterable, Sendable {
    case greaterThan, lessThan, between, notBetween, equal, notEqual, greaterThanOrEqual, lessThanOrEqual
}

public enum TextMatch: String, CaseIterable, Sendable {
    case containsText, notContainsText, beginsWith, endsWith
}

public enum ScaleValueKind: String, Sendable {
    case min, max, num, percent, percentile, formula
}

public struct ScaleStop: Hashable, Sendable {
    public var kind: ScaleValueKind
    public var value: String?
    public var color: RGBColor

    public init(_ kind: ScaleValueKind, _ value: String? = nil, color: RGBColor) {
        self.kind = kind
        self.value = value
        self.color = color
    }
}

public enum ConditionalRule: Hashable, Sendable {
    /// Compares the cell with one or two formulas (stored without `=`), relative to the first range's top-left cell.
    case cellIs(ComparisonOperator, String, String?, DifferentialStyle)
    case text(TextMatch, String, DifferentialStyle)
    case duplicates(unique: Bool, DifferentialStyle)
    case top(rank: Int, bottom: Bool, percent: Bool, DifferentialStyle)
    case average(below: Bool, DifferentialStyle)
    /// A formula (without `=`) that is true for highlighted cells.
    case expression(String, DifferentialStyle)
    case colorScale([ScaleStop])
    case dataBar(RGBColor)

    public var style: DifferentialStyle? {
        switch self {
        case .cellIs(_, _, _, let s), .text(_, _, let s), .duplicates(_, let s), .top(_, _, _, let s),
             .average(_, let s), .expression(_, let s):
            return s
        case .colorScale, .dataBar:
            return nil
        }
    }
}

public struct ConditionalFormat: Hashable, Sendable {
    public var ranges: [CellRange]
    public var rule: ConditionalRule
    public var stopIfTrue: Bool

    public init(ranges: [CellRange], rule: ConditionalRule, stopIfTrue: Bool = false) {
        self.ranges = ranges
        self.rule = rule
        self.stopIfTrue = stopIfTrue
    }

    var origin: CellAddress { ranges.first?.start ?? CellAddress(row: 0, column: 0) }
}

public struct DataBar: Hashable, Sendable {
    public let fraction: Double
    public let color: RGBColor
}

/// What conditional formatting does to one cell.
public struct ConditionalResult: Hashable, Sendable {
    public var style = DifferentialStyle()
    public var scaleColor: RGBColor?
    public var dataBar: DataBar?

    public var isEmpty: Bool { style.isEmpty && scaleColor == nil && dataBar == nil }
}

/// Values of a rule's ranges, gathered once per calculation.
struct ConditionalStats {
    var numbers: [Double] = []
    var counts: [String: Int] = [:]
}

extension Calculator {
    /// The combined effect of the sheet's rules on a cell; earlier rules win conflicts.
    public func conditionalFormatting(sheet index: Int, at address: CellAddress) -> ConditionalResult? {
        guard workbook.sheets.indices.contains(index) else { return nil }
        let rules = workbook.sheets[index].conditionalFormats
        guard !rules.isEmpty else { return nil }
        let key = Key(sheet: index, address: address)
        if let cached = conditionalCache[key] { return cached.isEmpty ? nil : cached }

        var result = ConditionalResult()
        for (ruleIndex, format) in rules.enumerated() where format.ranges.contains(where: { $0.contains(address) }) {
            switch format.rule {
            case .colorScale(let stops):
                if result.scaleColor == nil { result.scaleColor = scaleColor(stops, format, ruleIndex, index, address) }
            case .dataBar(let color):
                if result.dataBar == nil, let fraction = barFraction(format, ruleIndex, index, address) {
                    result.dataBar = DataBar(fraction: fraction, color: color)
                }
            default:
                guard matches(format, ruleIndex, index, address), let style = format.rule.style else { continue }
                result.style.merge(lowerPriority: style)
                if format.stopIfTrue { break }
            }
        }
        conditionalCache[key] = result
        return result.isEmpty ? nil : result
    }

    private func stats(_ format: ConditionalFormat, _ ruleIndex: Int, _ sheet: Int) -> ConditionalStats {
        let key = "\(sheet):\(ruleIndex)"
        if let cached = conditionalStats[key] { return cached }
        var stats = ConditionalStats()
        for range in format.ranges {
            for (address, value) in cells(in: range, sheet: sheet) {
                if case .number(let n) = value { stats.numbers.append(n) }
                stats.counts[displayText(sheet: sheet, at: address).lowercased(), default: 0] += 1
            }
        }
        stats.numbers.sort()
        conditionalStats[key] = stats
        return stats
    }

    /// Evaluates a rule formula as if written in the first range's top-left cell and copied to `address`.
    private func ruleValue(_ formula: String, _ format: ConditionalFormat, _ sheet: Int, _ address: CellAddress) -> CellValue {
        let origin = format.origin
        let raw = FormulaText.shifted("=" + formula, rows: address.row - origin.row, columns: address.column - origin.column)
        return evaluate(formula: raw, sheet: sheet, at: address)
    }

    private func matches(_ format: ConditionalFormat, _ ruleIndex: Int, _ sheet: Int, _ address: CellAddress) -> Bool {
        let value = value(sheet: sheet, at: address)
        switch format.rule {
        case .cellIs(let op, let first, let second, _):
            let cell = value == .empty ? .number(0) : value
            let a = ruleValue(first, format, sheet, address)
            if case .error = a { return false }
            switch op {
            case .between, .notBetween:
                guard let second else { return false }
                let b = ruleValue(second, format, sheet, address)
                let (low, high) = Calculator.compare(a, b) <= 0 ? (a, b) : (b, a)
                let inside = Calculator.compare(cell, low) >= 0 && Calculator.compare(cell, high) <= 0
                return op == .between ? inside : !inside
            case .equal: return Calculator.compare(cell, a) == 0
            case .notEqual: return Calculator.compare(cell, a) != 0
            case .greaterThan: return Calculator.compare(cell, a) > 0
            case .lessThan: return Calculator.compare(cell, a) < 0
            case .greaterThanOrEqual: return Calculator.compare(cell, a) >= 0
            case .lessThanOrEqual: return Calculator.compare(cell, a) <= 0
            }
        case .text(let match, let text, _):
            let shown = displayText(sheet: sheet, at: address).lowercased()
            let needle = text.lowercased()
            switch match {
            case .containsText: return value != .empty && shown.contains(needle)
            case .notContainsText: return !shown.contains(needle)
            case .beginsWith: return value != .empty && shown.hasPrefix(needle)
            case .endsWith: return value != .empty && shown.hasSuffix(needle)
            }
        case .duplicates(let unique, _):
            guard value != .empty else { return false }
            let count = stats(format, ruleIndex, sheet).counts[displayText(sheet: sheet, at: address).lowercased()] ?? 0
            return unique ? count == 1 : count > 1
        case .top(let rank, let bottom, let percent, _):
            guard case .number(let n) = value else { return false }
            let numbers = stats(format, ruleIndex, sheet).numbers
            guard !numbers.isEmpty else { return false }
            let count = percent ? max(1, Int(Double(numbers.count) * Double(rank) / 100)) : max(1, rank)
            let position = min(count, numbers.count) - 1
            return bottom ? n <= numbers[position] : n >= numbers[numbers.count - 1 - position]
        case .average(let below, _):
            guard case .number(let n) = value else { return false }
            let numbers = stats(format, ruleIndex, sheet).numbers
            guard !numbers.isEmpty else { return false }
            let mean = numbers.reduce(0, +) / Double(numbers.count)
            return below ? n < mean : n > mean
        case .expression(let formula, _):
            return (try? Calculator.boolean(ruleValue(formula, format, sheet, address))) ?? false
        case .colorScale, .dataBar:
            return false
        }
    }

    private func stopValue(_ stop: ScaleStop, _ numbers: [Double], _ format: ConditionalFormat, _ sheet: Int, _ address: CellAddress) -> Double? {
        guard let low = numbers.first, let high = numbers.last else { return nil }
        let given = stop.value.flatMap(Double.init)
        switch stop.kind {
        case .min: return low
        case .max: return high
        case .num: return given ?? stop.value.flatMap { try? Calculator.number(ruleValue($0, format, sheet, address)) }
        case .percent: return low + (high - low) * (given ?? 50) / 100
        case .percentile:
            let position = Double(numbers.count - 1) * (given ?? 50) / 100
            let lower = Int(position.rounded(.down))
            let upper = min(lower + 1, numbers.count - 1)
            return numbers[lower] + (numbers[upper] - numbers[lower]) * (position - Double(lower))
        case .formula: return stop.value.flatMap { try? Calculator.number(ruleValue($0, format, sheet, address)) }
        }
    }

    private func scaleColor(_ stops: [ScaleStop], _ format: ConditionalFormat, _ ruleIndex: Int, _ sheet: Int, _ address: CellAddress) -> RGBColor? {
        guard stops.count >= 2, case .number(let n) = value(sheet: sheet, at: address) else { return nil }
        let numbers = stats(format, ruleIndex, sheet).numbers
        let values = stops.compactMap { stopValue($0, numbers, format, sheet, address) }
        guard values.count == stops.count else { return nil }
        func blend(_ a: RGBColor, _ b: RGBColor, _ t: Double) -> RGBColor {
            let t = min(1, max(0, t.isFinite ? t : 0))
            func mix(_ x: UInt8, _ y: UInt8) -> UInt8 { UInt8((Double(x) + (Double(y) - Double(x)) * t).rounded()) }
            return RGBColor(red: mix(a.red, b.red), green: mix(a.green, b.green), blue: mix(a.blue, b.blue))
        }
        func position(_ v: Double, _ low: Double, _ high: Double) -> Double { high == low ? 1 : (v - low) / (high - low) }
        if stops.count == 2 || n <= values[1] {
            return blend(stops[0].color, stops[1].color, position(n, values[0], values[1]))
        }
        return blend(stops[1].color, stops[2].color, position(n, values[1], values[2]))
    }

    private func barFraction(_ format: ConditionalFormat, _ ruleIndex: Int, _ sheet: Int, _ address: CellAddress) -> Double? {
        guard case .number(let n) = value(sheet: sheet, at: address) else { return nil }
        let numbers = stats(format, ruleIndex, sheet).numbers
        guard let low = numbers.first, let high = numbers.last else { return nil }
        // Excel's automatic bars start at zero unless values are negative.
        let start = min(0, low)
        let end = max(0, high)
        guard end > start else { return 1 }
        return min(1, max(0, (n - start) / (end - start)))
    }
}
