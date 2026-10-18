import Foundation

public enum CellError: String, Error, Sendable, CaseIterable {
    case null = "#NULL!"
    case divideByZero = "#DIV/0!"
    case value = "#VALUE!"
    case reference = "#REF!"
    case name = "#NAME?"
    case number = "#NUM!"
    case notAvailable = "#N/A"
    /// Not an Excel error code: Excel warns about cycles instead of storing an error.
    case circular = "#CIRC!"
}

/// A computed cell value.
public enum CellValue: Equatable, Sendable {
    case empty
    case number(Double)
    case text(String)
    case boolean(Bool)
    case error(CellError)

    /// The value as Excel's General format displays it.
    public var displayText: String {
        switch self {
        case .empty: ""
        case .number(let n): NumberText.general(n)
        case .text(let s): s
        case .boolean(let b): b ? "TRUE" : "FALSE"
        case .error(let e): e.rawValue
        }
    }

    public var isNumber: Bool {
        if case .number = self { return true }
        return false
    }
}

/// Interprets what a user typed into a cell.
public enum CellInput {
    public static func isFormula(_ raw: String) -> Bool {
        raw.count > 1 && raw.hasPrefix("=")
    }

    /// The value of non-formula input. A leading apostrophe forces text.
    public static func literalValue(_ raw: String) -> CellValue {
        if raw.isEmpty { return .empty }
        if raw.hasPrefix("'") { return .text(String(raw.dropFirst())) }
        // Long text cannot be a number or boolean; skip the parsing work.
        if raw.utf8.count > 64 { return .text(raw) }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        switch trimmed.uppercased() {
        case "TRUE": return .boolean(true)
        case "FALSE": return .boolean(false)
        default: break
        }
        if let number = parseNumber(trimmed) { return .number(number) }
        return .text(raw)
    }

    /// Parses `1,234.5`, `12%`, `$5` and `-1e3`; rejects Swift-only forms such as `nan` or hex.
    public static func parseNumber(_ text: String) -> Double? {
        var s = text.replacingOccurrences(of: ",", with: "")
        var scale = 1.0
        if s.hasSuffix("%") { s.removeLast(); scale = 0.01 }
        var negative = false
        if s.hasPrefix("-$") { s.removeFirst(2); negative = true } else if s.hasPrefix("$") { s.removeFirst() }
        guard !s.isEmpty, s.allSatisfy({ "0123456789.eE+-".contains($0) }),
              let value = Double(s), value.isFinite else { return nil }
        return (negative ? -value : value) * scale
    }

    /// Input text that reproduces a literal value when typed back in.
    public static func rawInput(for value: CellValue) -> String {
        switch value {
        case .empty: return ""
        case .number(let n): return NumberText.roundTrip(n)
        case .boolean(let b): return b ? "TRUE" : "FALSE"
        case .error(let e): return e.rawValue
        case .text(let s):
            let needsQuote = s.hasPrefix("=") || literalValue(s) != .text(s)
            return needsQuote ? "'" + s : s
        }
    }
}

enum NumberText {
    static func general(_ value: Double) -> String {
        if value == 0 { return "0" }
        if value.rounded() == value, abs(value) < 1e15 { return String(Int64(value)) }
        return String(format: "%.10G", value)
    }

    static func roundTrip(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 { return String(Int64(value)) }
        return "\(value)"
    }

    /// Inserts thousands separators into a run of digits.
    static func group(_ digits: String) -> String {
        var chars = Array(digits)
        var index = chars.count - 3
        while index > 0 {
            chars.insert(",", at: index)
            index -= 3
        }
        return String(chars)
    }
}

/// Conversions between Excel serial dates (days since 1899-12-30) and calendar dates.
enum DateMath {
    static func civil(serial: Double) -> (year: Int, month: Int, day: Int)? {
        guard serial >= 1, serial < 2_958_466 else { return nil }
        // Civil-from-days conversion (Howard Hinnant), from Unix days.
        let z = Int(serial.rounded(.down)) - 25_569 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let mp = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        return (yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }

    /// Like Excel's DATE: months and days outside their ranges roll over.
    static func serial(year: Int, month: Int, day: Int) -> Double {
        let monthIndex = month - 1
        let y = year + Int((Double(monthIndex) / 12).rounded(.down))
        let m = ((monthIndex % 12) + 12) % 12 + 1
        // Days-from-civil (Howard Hinnant).
        let yy = m <= 2 ? y - 1 : y
        let era = (yy >= 0 ? yy : yy - 399) / 400
        let yearOfEra = yy - era * 400
        let dayOfYear = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        let unixDays = era * 146_097 + dayOfEra - 719_468
        return Double(unixDays + 25_569 + day - 1)
    }
}
