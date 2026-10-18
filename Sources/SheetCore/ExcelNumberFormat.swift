import Foundation

public struct FormattedValue: Equatable, Sendable {
    public let text: String
    /// A color picked by the format itself, such as `[Red]`.
    public let color: RGBColor?

    public init(text: String, color: RGBColor?) {
        self.text = text
        self.color = color
    }
}

/// Renders values with Excel number format codes: up to four `;`-separated sections
/// (positive; negative; zero; text), literals, colors, conditions, digit placeholders,
/// grouping and scaling commas, percent, scientific, fractions, dates, times and elapsed time.
public enum ExcelNumberFormat {
    public static let builtIn: [Int: String] = [
        0: "General", 1: "0", 2: "0.00", 3: "#,##0", 4: "#,##0.00",
        5: ##""$"#,##0_);\("$"#,##0\)"##, 6: ##""$"#,##0_);[Red]\("$"#,##0\)"##,
        7: ##""$"#,##0.00_);\("$"#,##0.00\)"##, 8: ##""$"#,##0.00_);[Red]\("$"#,##0.00\)"##,
        9: "0%", 10: "0.00%", 11: "0.00E+00", 12: "# ?/?", 13: "# ??/??",
        14: "m/d/yyyy", 15: "d-mmm-yy", 16: "d-mmm", 17: "mmm-yy",
        18: "h:mm AM/PM", 19: "h:mm:ss AM/PM", 20: "h:mm", 21: "h:mm:ss", 22: "m/d/yyyy h:mm",
        37: "#,##0 ;(#,##0)", 38: "#,##0 ;[Red](#,##0)", 39: "#,##0.00;(#,##0.00)", 40: "#,##0.00;[Red](#,##0.00)",
        41: #"_(* #,##0_);_(* \(#,##0\);_(* "-"_);_(@_)"#,
        42: #"_("$"* #,##0_);_("$"* \(#,##0\);_("$"* "-"_);_(@_)"#,
        43: #"_(* #,##0.00_);_(* \(#,##0.00\);_(* "-"??_);_(@_)"#,
        44: #"_("$"* #,##0.00_);_("$"* \(#,##0.00\);_("$"* "-"??_);_(@_)"#,
        45: "mm:ss", 46: "[h]:mm:ss", 47: "mm:ss.0", 48: "##0.0E+0", 49: "@",
    ]

    public static func builtInID(for code: String) -> Int? {
        builtIn.first { $0.value == code }?.key
    }

    public static func format(_ value: CellValue, code: String) -> FormattedValue {
        let sections = parsed(code)
        switch value {
        case .number(let n):
            return formatNumber(n, sections)
        case .text(let s):
            if sections.count >= 4 { return renderText(s, sections[3]) }
            if sections.count == 1, sections[0].tokens.contains(.text) { return renderText(s, sections[0]) }
            return FormattedValue(text: s, color: nil)
        case .empty, .boolean, .error:
            return FormattedValue(text: value.displayText, color: nil)
        }
    }

    /// Whether a code shows numbers as dates or times.
    public static func isDate(_ code: String) -> Bool {
        parsed(code).contains { $0.isDate }
    }

    /// Adds or removes one decimal place in every numeric section, like Excel's decimal buttons.
    public static func adjustingDecimals(_ code: String, by delta: Int) -> String {
        if code.isEmpty || code.caseInsensitiveCompare("General") == .orderedSame { return delta > 0 ? "0.0" : "0" }
        return splitSections(code).map { section in
            parseSection(section).isDate ? section : adjustSection(section, delta)
        }.joined(separator: ";")
    }

    // MARK: - Parsing

    enum Token: Equatable {
        case literal(String)
        case digit(Character)
        case decimalPoint
        case comma
        case percent
        /// `E+` (always signed) or `E-`.
        case exponent(alwaysSigned: Bool)
        case text
        case general
        /// A lowercased date/time code: `yyyy`, `m`, `dddd`, `hh`, `ss`, `am/pm`, `a/p`.
        case date(String)
        /// `[h]`, `[mm]`, `[ss]`.
        case elapsed(Character, Int)
        case fractionBar
    }

    struct Section {
        var tokens: [Token] = []
        var color: RGBColor?
        var condition: (op: String, value: Double)?

        var isDate: Bool {
            tokens.contains { token in
                switch token {
                case .date, .elapsed: return true
                default: return false
                }
            }
        }
    }

    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var sections: [String: [Section]] = [:]
    }

    private static let cache = Cache()

    static func parsed(_ code: String) -> [Section] {
        cache.lock.lock()
        defer { cache.lock.unlock() }
        if let hit = cache.sections[code] { return hit }
        let sections = splitSections(code).map(parseSection)
        if cache.sections.count > 2_000 { cache.sections.removeAll() }
        cache.sections[code] = sections
        return sections
    }

    static func splitSections(_ code: String) -> [String] {
        var sections: [String] = []
        var current = ""
        var inQuote = false
        var inBracket = false
        var escaped = false
        for c in code {
            if escaped {
                current.append(c)
                escaped = false
                continue
            }
            if c == "\\" && !inQuote {
                escaped = true
                current.append(c)
                continue
            }
            if c == "\"" { inQuote.toggle() }
            if !inQuote && c == "[" { inBracket = true }
            if !inQuote && c == "]" { inBracket = false }
            if c == ";" && !inQuote && !inBracket {
                sections.append(current)
                current = ""
            } else {
                current.append(c)
            }
        }
        sections.append(current)
        return sections
    }

    private static let namedColors: [String: RGBColor] = [
        "black": RGBColor(red: 0, green: 0, blue: 0), "white": RGBColor(red: 255, green: 255, blue: 255),
        "red": RGBColor(red: 255, green: 0, blue: 0), "green": RGBColor(red: 0, green: 128, blue: 0),
        "blue": RGBColor(red: 0, green: 0, blue: 255), "yellow": RGBColor(red: 255, green: 255, blue: 0),
        "magenta": RGBColor(red: 255, green: 0, blue: 255), "cyan": RGBColor(red: 0, green: 255, blue: 255),
    ]

    static func parseSection(_ text: String) -> Section {
        var section = Section()
        let chars = Array(text)
        var i = 0

        func literal(_ s: String) {
            if case .literal(let previous)? = section.tokens.last {
                section.tokens[section.tokens.count - 1] = .literal(previous + s)
            } else {
                section.tokens.append(.literal(s))
            }
        }

        while i < chars.count {
            let c = chars[i]
            switch c {
            case "\"":
                var j = i + 1
                var quoted = ""
                while j < chars.count, chars[j] != "\"" {
                    quoted.append(chars[j])
                    j += 1
                }
                literal(quoted)
                i = j + 1
                continue
            case "\\":
                if i + 1 < chars.count { literal(String(chars[i + 1])) }
                i += 2
                continue
            case "_":
                // Space the width of the next character, used to line up parentheses.
                literal(" ")
                i += 2
                continue
            case "*":
                // Repeat-to-fill: cells are not padded, so the fill character appears once.
                if i + 1 < chars.count { literal(String(chars[i + 1])) }
                i += 2
                continue
            case "[":
                var j = i + 1
                var inside = ""
                while j < chars.count, chars[j] != "]" {
                    inside.append(chars[j])
                    j += 1
                }
                i = j + 1
                let lower = inside.lowercased()
                if let color = namedColors[lower] {
                    section.color = color
                } else if lower.hasPrefix("color"), let index = Int(lower.dropFirst(5)) {
                    section.color = IndexedColors.color(index)
                } else if inside.hasPrefix("$") {
                    let symbol = inside.dropFirst().split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
                    if !symbol.isEmpty { literal(symbol) }
                } else if let first = lower.first, "<>=".contains(first) {
                    let op = String(lower.prefix { "<>=".contains($0) })
                    if let value = Double(lower.dropFirst(op.count)) { section.condition = (op, value) }
                } else if let unit = lower.first, "hms".contains(unit), lower.allSatisfy({ $0 == unit }) {
                    section.tokens.append(.elapsed(unit, lower.count))
                }
                continue
            case "0", "#", "?":
                section.tokens.append(.digit(c))
            case ".":
                section.tokens.append(.decimalPoint)
            case ",":
                section.tokens.append(.comma)
            case "%":
                section.tokens.append(.percent)
            case "@":
                section.tokens.append(.text)
            case "/":
                if case .digit? = section.tokens.last, i + 1 < chars.count, "0#?123456789".contains(chars[i + 1]) {
                    section.tokens.append(.fractionBar)
                } else {
                    literal("/")
                }
            case "E", "e":
                if i + 1 < chars.count, chars[i + 1] == "+" || chars[i + 1] == "-" {
                    section.tokens.append(.exponent(alwaysSigned: chars[i + 1] == "+"))
                    i += 2
                    continue
                }
                if c == "e" { section.tokens.append(.date("yyyy")) } else { literal("E") }
            case "G", "g":
                if String(chars[i...]).uppercased().hasPrefix("GENERAL") {
                    section.tokens.append(.general)
                    i += 7
                    continue
                }
                literal(String(c))
            case "A", "a":
                let rest = String(chars[i...]).uppercased()
                if rest.hasPrefix("AM/PM") {
                    section.tokens.append(.date("am/pm"))
                    i += 5
                    continue
                }
                if rest.hasPrefix("A/P") {
                    section.tokens.append(.date("a/p"))
                    i += 3
                    continue
                }
                literal(String(c))
            case "y", "Y", "m", "M", "d", "D", "h", "H", "s", "S":
                let lower = Character(c.lowercased())
                var j = i
                while j < chars.count, Character(chars[j].lowercased()) == lower { j += 1 }
                section.tokens.append(.date(String(repeating: lower, count: j - i)))
                i = j
                continue
            default:
                literal(String(c))
            }
            i += 1
        }
        return section
    }

    // MARK: - Numbers

    private static func formatNumber(_ n: Double, _ sections: [Section]) -> FormattedValue {
        var section = sections[0]
        var value = n
        var signShown = false

        if sections.contains(where: { $0.condition != nil }) {
            let match = sections.first { candidate in
                guard let condition = candidate.condition else { return false }
                return matches(n, condition)
            }
            section = match ?? sections.first { $0.condition == nil } ?? sections[sections.count - 1]
            // A section chosen for negative values shows them without a minus sign.
            if n < 0, let condition = section.condition, condition.op.contains("<") {
                value = abs(n)
                signShown = true
            }
        } else if sections.count >= 2, n < 0 {
            section = sections[1]
            value = abs(n)
            signShown = true
        } else if sections.count >= 3, n == 0 {
            section = sections[2]
        }

        let tokens = section.tokens
        if tokens.isEmpty { return FormattedValue(text: "", color: section.color) }

        if section.isDate {
            guard let text = formatDate(n, tokens) else {
                return FormattedValue(text: NumberText.general(n), color: section.color)
            }
            return FormattedValue(text: text, color: section.color)
        }

        let hasDigits = tokens.contains { if case .digit = $0 { true } else { false } }
        if tokens.contains(.general) || (!hasDigits && tokens.contains(.text)) {
            let number = NumberText.general(signShown ? value : n)
            let text = tokens.contains(.general) ? render(tokens, number: number, skippingInterior: false) : number
            return FormattedValue(text: text, color: section.color)
        }
        guard hasDigits else { return FormattedValue(text: render(tokens, number: "", skippingInterior: false), color: section.color) }

        let result = digits(value: signShown ? value : abs(n), tokens)
        let sign = (!signShown && n < 0 && !result.isZero) ? "-" : ""
        let text = render(tokens, number: result.text, skippingInterior: result.includesLiterals)
        return FormattedValue(text: sign + text, color: section.color)
    }

    private static func matches(_ n: Double, _ condition: (op: String, value: Double)) -> Bool {
        switch condition.op {
        case "<": n < condition.value
        case "<=", "=<": n <= condition.value
        case ">": n > condition.value
        case ">=", "=>": n >= condition.value
        case "<>": n != condition.value
        default: n == condition.value
        }
    }

    /// Places the formatted number where the digit placeholders were, keeping the literals around them.
    private static func render(_ tokens: [Token], number: String, skippingInterior: Bool) -> String {
        let placeholders = tokens.indices.filter { if case .digit = tokens[$0] { true } else { false } }
        var interior = skippingInterior ? placeholders.first.flatMap { first in placeholders.last.map { first...$0 } } : nil
        // A fixed fraction denominator such as the 8 in "# ?/8" is part of the number.
        if let range = interior, let bar = tokens.firstIndex(of: .fractionBar), bar + 1 < tokens.count,
           case .literal(let s) = tokens[bar + 1], s.first?.isNumber == true {
            interior = range.lowerBound...max(range.upperBound, bar + 1)
        }
        var output = ""
        var placed = false
        var inNumber = false
        for (index, token) in tokens.enumerated() {
            switch token {
            case .literal(let s):
                if interior?.contains(index) == true { continue }
                output += s
                inNumber = false
            case .percent:
                output += "%"
            case .general, .digit, .decimalPoint, .exponent, .fractionBar:
                if !placed {
                    output += number
                    placed = true
                }
                inNumber = true
            case .comma:
                if !inNumber && !placed { output += "," }
            case .text, .date, .elapsed:
                break
            }
        }
        return output
    }

    private struct Digits {
        let text: String
        let isZero: Bool
        /// The text already contains the literals between the first and last placeholder.
        var includesLiterals = false
    }

    private static func digits(value: Double, _ tokens: [Token]) -> Digits {
        let (text, isZero, includesLiterals) = digitText(value: value, tokens)
        return Digits(text: text, isZero: isZero, includesLiterals: includesLiterals)
    }

    /// The digits for a non-negative value, whether it rounds to zero, and whether interior literals were placed.
    private static func digitText(value: Double, _ tokens: [Token]) -> (String, Bool, Bool) {
        var scaled = value * pow(100, Double(tokens.filter { $0 == .percent }.count))

        let placeholderIndices = tokens.indices.filter { if case .digit = tokens[$0] { true } else { false } }
        let last = placeholderIndices.last!
        var trailing = last + 1
        while trailing < tokens.count, tokens[trailing] == .comma {
            scaled /= 1000
            trailing += 1
        }

        if let exponentIndex = tokens.firstIndex(where: { if case .exponent = $0 { true } else { false } }) {
            let result = scientific(scaled, tokens, exponentIndex: exponentIndex)
            return (result.0, result.1, false)
        }
        if let bar = tokens.firstIndex(of: .fractionBar) {
            let result = fraction(scaled, tokens, bar: bar)
            return (result.0, result.1, true)
        }

        let point = tokens.firstIndex(of: .decimalPoint)
        let integerPlaceholders = placeholderIndices.filter { point == nil || $0 < point! }.map { placeholder(tokens[$0]) }
        let decimalPlaceholders = placeholderIndices.filter { point != nil && $0 > point! }.map { placeholder(tokens[$0]) }
        let first = placeholderIndices.first!
        let integerEnd = point ?? last
        let grouping = (first..<integerEnd).contains { tokens[$0] == .comma }
        let interiorLiterals = (first...last).contains { if case .literal = tokens[$0] { true } else { false } }

        let fixed = String(format: "%.\(decimalPlaceholders.count)f", roundedHalfAway(scaled, decimalPlaceholders.count))
        let parts = fixed.split(separator: ".", maxSplits: 1)
        var integer = String(parts[0])
        var fractionDigits = parts.count > 1 ? Array(parts[1]) : []
        let isZero = fixed.allSatisfy { $0 == "0" || $0 == "." }

        // Formats like 000-0000 spread digits across literals.
        if interiorLiterals && point == nil && !grouping {
            var digits = Array(integer == "0" ? "" : integer)
            let required = integerPlaceholders.filter { $0 == "0" }.count
            while digits.count < required { digits.insert("0", at: 0) }
            var output = ""
            var remaining = digits
            for index in stride(from: last, through: first, by: -1) {
                switch tokens[index] {
                case .digit:
                    if index == first {
                        output = String(remaining) + output
                        remaining = []
                    } else if let digit = remaining.popLast() {
                        output = String(digit) + output
                    }
                case .literal(let s):
                    output = s + output
                default:
                    break
                }
            }
            return (output, isZero, true)
        }

        let minimum = integerPlaceholders.filter { $0 == "0" }.count
        let padded = integerPlaceholders.filter { $0 != "#" }.count
        if integer == "0" && minimum == 0 { integer = "" }
        while integer.count < minimum { integer = "0" + integer }
        if grouping { integer = NumberText.group(integer) }
        while integer.count < padded { integer = " " + integer }

        for (index, kind) in decimalPlaceholders.enumerated().reversed() {
            guard fractionDigits[index] == "0" else { break }
            if kind == "#" {
                fractionDigits.remove(at: index)
            } else if kind == "?" {
                fractionDigits[index] = " "
            } else {
                break
            }
        }
        return (integer + (point != nil ? "." + String(fractionDigits) : ""), isZero, false)
    }

    /// Excel rounds halves away from zero; binary noise is dropped first so 2.675 rounds to 2.68.
    private static func roundedHalfAway(_ value: Double, _ decimals: Int) -> Double {
        let factor = pow(10, Double(decimals))
        let scaled = Double(String(format: "%.15g", value * factor)) ?? value * factor
        return scaled.rounded(.toNearestOrAwayFromZero) / factor
    }

    private static func placeholder(_ token: Token) -> Character {
        if case .digit(let c) = token { return c }
        return "0"
    }

    private static func scientific(_ value: Double, _ tokens: [Token], exponentIndex: Int) -> (String, Bool) {
        let point = tokens.firstIndex(of: .decimalPoint).flatMap { $0 < exponentIndex ? $0 : nil }
        let mantissaPlaceholders = tokens[..<exponentIndex].filter { if case .digit = $0 { true } else { false } }.count
        let integerPlaceholders = point.map { p in tokens[..<p].filter { if case .digit = $0 { true } else { false } }.count } ?? mantissaPlaceholders
        let decimals = mantissaPlaceholders - integerPlaceholders
        let exponentDigits = tokens[(exponentIndex + 1)...].filter { if case .digit = $0 { true } else { false } }.count
        guard case .exponent(let alwaysSigned) = tokens[exponentIndex] else { return ("", true) }

        var exponent = value == 0 ? 0 : Int(log10(value).rounded(.down))
        if integerPlaceholders > 1 {
            let step = integerPlaceholders
            exponent = Int((Double(exponent) / Double(step)).rounded(.down)) * step
        }
        var mantissa = value / pow(10, Double(exponent))
        let rounded = Double(String(format: "%.\(decimals)f", mantissa)) ?? mantissa
        if integerPlaceholders <= 1, rounded >= 10 {
            exponent += 1
            mantissa = value / pow(10, Double(exponent))
        }
        let mantissaText = String(format: "%.\(decimals)f", mantissa)
        var exponentText = String(abs(exponent))
        while exponentText.count < max(exponentDigits, 1) { exponentText = "0" + exponentText }
        let sign = exponent < 0 ? "-" : (alwaysSigned ? "+" : "")
        return (mantissaText + "E" + sign + exponentText, value == 0)
    }

    private static func fraction(_ value: Double, _ tokens: [Token], bar: Int) -> (String, Bool) {
        // An integer part exists when a literal separates two groups of placeholders before the bar.
        let before = tokens[..<bar]
        let groups = before.split { if case .literal = $0 { true } else { false } }.filter { group in
            group.contains { if case .digit = $0 { true } else { false } }
        }
        let hasInteger = groups.count >= 2
        var denominatorDigits = 0
        var fixedDenominator: Int?
        for token in tokens[(bar + 1)...] {
            if case .digit = token {
                denominatorDigits += 1
            } else if case .literal(let s) = token, denominatorDigits == 0 {
                fixedDenominator = Int(s.prefix { $0.isNumber })
                break
            } else {
                break
            }
        }
        var whole = hasInteger ? value.rounded(.down) : 0
        let remainder = value - whole
        var bestNumerator = 0
        var bestDenominator = 1
        if let fixedDenominator, fixedDenominator > 0 {
            bestDenominator = fixedDenominator
            bestNumerator = Int((remainder * Double(fixedDenominator)).rounded())
        } else {
            let maxDenominator = max(1, Int(pow(10, Double(max(denominatorDigits, 1)))) - 1)
            var bestError = Double.infinity
            for denominator in 1...maxDenominator {
                let numerator = (remainder * Double(denominator)).rounded()
                let error = abs(remainder - numerator / Double(denominator))
                if error < bestError - 1e-12 {
                    bestError = error
                    bestNumerator = Int(numerator)
                    bestDenominator = denominator
                }
            }
        }
        if hasInteger, bestNumerator == bestDenominator {
            whole += 1
            bestNumerator = 0
        }
        if !hasInteger {
            return ("\(bestNumerator)/\(bestDenominator)", bestNumerator == 0)
        }
        let wholeText = whole == 0 && bestNumerator != 0 ? "" : String(Int(whole))
        if bestNumerator == 0 { return (wholeText, whole == 0) }
        return ((wholeText.isEmpty ? "" : wholeText + " ") + "\(bestNumerator)/\(bestDenominator)", false)
    }

    private static func renderText(_ text: String, _ section: Section) -> FormattedValue {
        var output = ""
        for token in section.tokens {
            switch token {
            case .literal(let s): output += s
            case .text: output += text
            default: break
            }
        }
        return FormattedValue(text: output, color: section.color)
    }

    // MARK: - Dates and times

    private static let monthNames = ["January", "February", "March", "April", "May", "June", "July",
                                     "August", "September", "October", "November", "December"]
    private static let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    private static func formatDate(_ serial: Double, _ tokens: [Token]) -> String? {
        guard serial >= 0, serial < 2_958_466 else { return nil }
        var days = Int(serial.rounded(.down))
        let exactSeconds = (serial - Double(days)) * 86_400
        var seconds = Int(exactSeconds.rounded())
        if seconds >= 86_400 {
            days += 1
            seconds -= 86_400
        }
        let civil = days >= 1 ? DateMath.civil(serial: Double(days)) ?? (1900, 1, 0) : (1900, 1, 0)
        let (year, month, day) = (civil.0, civil.1, civil.2)
        let hour = seconds / 3600
        let minute = seconds % 3600 / 60
        let second = seconds % 60
        let weekday = ((days - 25_569 + 4) % 7 + 7) % 7
        let twelveHour = tokens.contains(.date("am/pm")) || tokens.contains(.date("a/p"))

        func pad(_ n: Int, _ width: Int) -> String {
            let text = String(n)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }

        var output = ""
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            switch token {
            case .literal(let s):
                output += s
            case .date(let code):
                switch code.first {
                case "y":
                    output += code.count <= 2 ? pad(year % 100, 2) : pad(year, 4)
                case "m":
                    if isMinute(index, tokens) {
                        output += pad(minute, min(code.count, 2))
                    } else {
                        switch code.count {
                        case 1: output += String(month)
                        case 2: output += pad(month, 2)
                        case 3: output += String(monthNames[month - 1].prefix(3))
                        case 4: output += monthNames[month - 1]
                        default: output += String(monthNames[month - 1].prefix(1))
                        }
                    }
                case "d":
                    switch code.count {
                    case 1: output += String(day)
                    case 2: output += pad(day, 2)
                    case 3: output += String(dayNames[weekday].prefix(3))
                    default: output += dayNames[weekday]
                    }
                case "h":
                    let shown = twelveHour ? (hour % 12 == 0 ? 12 : hour % 12) : hour
                    output += pad(shown, min(code.count, 2))
                case "s":
                    output += pad(second, min(code.count, 2))
                case "a":
                    output += code == "am/pm" ? (hour < 12 ? "AM" : "PM") : (hour < 12 ? "A" : "P")
                default:
                    break
                }
            case .elapsed(let unit, let width):
                let total = Double(days) * 86_400 + Double(seconds)
                let amount = switch unit {
                case "h": Int(total / 3600)
                case "m": Int(total / 60)
                default: Int(total)
                }
                output += pad(amount, width)
            case .decimalPoint:
                // Fractional seconds, as in mm:ss.0
                var places = 0
                while index + 1 < tokens.count, case .digit = tokens[index + 1] {
                    places += 1
                    index += 1
                }
                let fraction = exactSeconds - exactSeconds.rounded(.down)
                let digits = String(format: "%.\(places)f", fraction).dropFirst(1)
                output += places > 0 ? String(digits) : "."
            case .percent:
                output += "%"
            case .comma:
                output += ","
            default:
                break
            }
            index += 1
        }
        return output
    }

    /// `m` means minutes right after hours or right before seconds.
    private static func isMinute(_ index: Int, _ tokens: [Token]) -> Bool {
        for token in tokens[..<index].reversed() {
            if case .date(let code) = token { return code.first == "h" }
            if case .elapsed(let unit, _) = token { return unit == "h" }
        }
        for token in tokens[(index + 1)...] {
            if case .date(let code) = token { return code.first == "s" }
            if case .elapsed(let unit, _) = token { return unit == "s" }
        }
        return false
    }

    // MARK: - Decimal buttons

    private static func adjustSection(_ section: String, _ delta: Int) -> String {
        var chars = Array(section)
        var placeholders: [Int] = []
        var point: Int?
        var inQuote = false
        var inBracket = false
        var index = 0
        while index < chars.count {
            let c = chars[index]
            if c == "\\" || c == "_" || c == "*" {
                index += 2
                continue
            }
            if c == "\"" { inQuote.toggle() }
            if !inQuote {
                if c == "[" { inBracket = true }
                if c == "]" { inBracket = false }
                if !inBracket {
                    if "0#?".contains(c) { placeholders.append(index) }
                    if c == ".", !placeholders.isEmpty, point == nil { point = index }
                }
            }
            index += 1
        }
        guard let last = placeholders.last else { return section }
        if let point, last > point {
            if delta > 0 {
                chars.insert("0", at: last + 1)
            } else {
                chars.remove(at: last)
                if !placeholders.contains(where: { $0 > point && $0 != last }) { chars.remove(at: point) }
            }
        } else if delta > 0 {
            chars.insert(contentsOf: ".0", at: last + 1)
        }
        return String(chars)
    }
}

/// Excel's legacy 64-color palette, used by `indexed` colors and `[ColorN]`.
public enum IndexedColors {
    static let palette: [String] = [
        "000000", "FFFFFF", "FF0000", "00FF00", "0000FF", "FFFF00", "FF00FF", "00FFFF",
        "000000", "FFFFFF", "FF0000", "00FF00", "0000FF", "FFFF00", "FF00FF", "00FFFF",
        "800000", "008000", "000080", "808000", "800080", "008080", "C0C0C0", "808080",
        "9999FF", "993366", "FFFFCC", "CCFFFF", "660066", "FF8080", "0066CC", "CCCCFF",
        "000080", "FF00FF", "FFFF00", "00FFFF", "800080", "800000", "008080", "0000FF",
        "00CCFF", "CCFFFF", "CCFFCC", "FFFF99", "99CCFF", "FF99CC", "CC99FF", "FFCC99",
        "3366FF", "33CCCC", "99CC00", "FFCC00", "FF9900", "FF6600", "666699", "969696",
        "003366", "339966", "003300", "333300", "993300", "993366", "333399", "333333",
    ]

    /// `[ColorN]` counts from 1 at palette index 8; `indexed` values use the palette directly.
    static func color(_ formatIndex: Int) -> RGBColor? {
        palette.indices.contains(formatIndex + 7) ? RGBColor(hex: palette[formatIndex + 7]) : nil
    }

    static func indexed(_ index: Int) -> RGBColor? {
        palette.indices.contains(index) ? RGBColor(hex: palette[index]) : nil
    }
}
