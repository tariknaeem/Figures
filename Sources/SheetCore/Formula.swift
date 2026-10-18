import Foundation

/// A parsed formula expression.
public indirect enum Expr: Equatable, Sendable {
    case number(Double)
    case text(String)
    case boolean(Bool)
    case error(CellError)
    case reference(sheet: String?, CellAddress)
    case range(sheet: String?, CellRange)
    case negate(Expr)
    case percent(Expr)
    case binary(BinaryOperator, Expr, Expr)
    case call(String, [Expr])
    /// A defined name such as `TaxRate`.
    case name(String)
    /// An omitted argument, as in `IF(A1, 1,)`.
    case missing
    /// An array constant such as `{1,2;3,4}`, row by row.
    case array([[CellValue]])
    /// A 3D reference across consecutive sheets, such as `Jan:Mar!B2:B5`.
    case sheetSpan(first: String, last: String, CellRange)
}

public enum BinaryOperator: String, Sendable {
    case add = "+", subtract = "-", multiply = "*", divide = "/", power = "^", concat = "&"
    case equal = "=", notEqual = "<>", less = "<", lessOrEqual = "<=", greater = ">", greaterOrEqual = ">="
}

struct FormulaToken: Equatable {
    enum Kind: Equatable {
        case number(Double)
        case text(String)
        case error(CellError)
        /// A function name, reference, column or boolean.
        case word(String)
        /// A sheet qualifier such as `Sheet2!` or `'My Sheet'!`.
        case sheet(String)
        case op(String)
        case leftParen, rightParen, comma, colon
        case leftBrace, rightBrace, semicolon
    }

    var kind: Kind
    /// Character offsets in the formula source.
    var range: Range<Int>
}

struct FormulaSyntaxError: Error {}

enum FormulaLexer {
    static func tokenize(_ chars: [Character], from start: Int) throws -> [FormulaToken] {
        var tokens: [FormulaToken] = []
        var i = start
        let n = chars.count

        func isDigit(_ index: Int) -> Bool { index < n && chars[index].isASCII && chars[index].isNumber }

        while i < n {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            let begin = i
            let kind: FormulaToken.Kind

            if isDigit(i) || (c == "." && isDigit(i + 1)) {
                while isDigit(i) { i += 1 }
                if i < n, chars[i] == "." {
                    i += 1
                    while isDigit(i) { i += 1 }
                }
                if i < n, chars[i] == "e" || chars[i] == "E" {
                    var j = i + 1
                    if j < n, chars[j] == "+" || chars[j] == "-" { j += 1 }
                    if isDigit(j) {
                        i = j
                        while isDigit(i) { i += 1 }
                    }
                }
                guard let value = Double(String(chars[begin..<i])) else { throw FormulaSyntaxError() }
                kind = .number(value)
            } else if c == "\"" || c == "'" {
                var text = ""
                i += 1
                while true {
                    guard i < n else { throw FormulaSyntaxError() }
                    if chars[i] == c {
                        if i + 1 < n, chars[i + 1] == c {
                            text.append(c)
                            i += 2
                            continue
                        }
                        i += 1
                        break
                    }
                    text.append(chars[i])
                    i += 1
                }
                if c == "\"" {
                    kind = .text(text)
                } else {
                    guard i < n, chars[i] == "!" else { throw FormulaSyntaxError() }
                    i += 1
                    kind = .sheet(text)
                }
            } else if c == "#" {
                let rest = String(chars[i...]).uppercased()
                guard let error = CellError.allCases.first(where: { rest.hasPrefix($0.rawValue) }) else {
                    throw FormulaSyntaxError()
                }
                i += error.rawValue.count
                kind = .error(error)
            } else if c.isLetter || c == "_" || c == "$" || c == "\\" {
                while i < n, chars[i].isLetter || chars[i].isNumber || "_.$\\".contains(chars[i]) { i += 1 }
                let word = String(chars[begin..<i])
                if i < n, chars[i] == "!" {
                    i += 1
                    kind = .sheet(word)
                } else {
                    kind = .word(word)
                }
            } else {
                i += 1
                switch c {
                case "(": kind = .leftParen
                case ")": kind = .rightParen
                case ",": kind = .comma
                case "{": kind = .leftBrace
                case "}": kind = .rightBrace
                case ";": kind = .semicolon
                case ":": kind = .colon
                case "<" where i < n && (chars[i] == ">" || chars[i] == "="),
                     ">" where i < n && chars[i] == "=":
                    kind = .op(String(c) + String(chars[i]))
                    i += 1
                case "+", "-", "*", "/", "^", "&", "=", "<", ">", "%":
                    kind = .op(String(c))
                default:
                    throw FormulaSyntaxError()
                }
            }
            tokens.append(FormulaToken(kind: kind, range: begin..<i))
        }
        return tokens
    }
}

struct FormulaParser {
    private let tokens: [FormulaToken]
    private var index = 0

    private init(tokens: [FormulaToken]) {
        self.tokens = tokens
    }

    /// Parses raw cell input that starts with `=`.
    static func parse(_ raw: String) -> Result<Expr, CellError> {
        let chars = Array(raw)
        guard chars.first == "=" else { return .failure(.value) }
        do {
            var parser = FormulaParser(tokens: try FormulaLexer.tokenize(chars, from: 1))
            let expr = try parser.comparison()
            guard parser.index == parser.tokens.count else { return .failure(.name) }
            return .success(expr)
        } catch let error as CellError {
            return .failure(error)
        } catch {
            return .failure(.name)
        }
    }

    private var peek: FormulaToken.Kind? { index < tokens.count ? tokens[index].kind : nil }

    private mutating func next() throws -> FormulaToken.Kind {
        guard index < tokens.count else { throw FormulaSyntaxError() }
        defer { index += 1 }
        return tokens[index].kind
    }

    private mutating func binaryLevel(
        _ operators: Set<String>,
        _ operand: (inout FormulaParser) throws -> Expr
    ) throws -> Expr {
        var lhs = try operand(&self)
        while case .op(let symbol)? = peek, operators.contains(symbol), let op = BinaryOperator(rawValue: symbol) {
            index += 1
            lhs = .binary(op, lhs, try operand(&self))
        }
        return lhs
    }

    // Excel precedence, loosest first: comparison, &, + -, * /, ^, unary minus, %.
    private mutating func comparison() throws -> Expr {
        try binaryLevel(["=", "<>", "<", "<=", ">", ">="]) { try $0.concatenation() }
    }

    private mutating func concatenation() throws -> Expr {
        try binaryLevel(["&"]) { try $0.additive() }
    }

    private mutating func additive() throws -> Expr {
        try binaryLevel(["+", "-"]) { try $0.multiplicative() }
    }

    private mutating func multiplicative() throws -> Expr {
        try binaryLevel(["*", "/"]) { try $0.power() }
    }

    private mutating func power() throws -> Expr {
        try binaryLevel(["^"]) { try $0.unary() }
    }

    /// Unary minus binds tighter than `^` in Excel, so `-2^2` is 4.
    private mutating func unary() throws -> Expr {
        if case .op("-")? = peek {
            index += 1
            return .negate(try unary())
        }
        if case .op("+")? = peek {
            index += 1
            return try unary()
        }
        var expr = try primary()
        while case .op("%")? = peek {
            index += 1
            expr = .percent(expr)
        }
        return expr
    }

    private mutating func primary() throws -> Expr {
        switch try next() {
        case .number(let value):
            // A row range such as 1:3.
            if case .colon? = peek, let first = Self.rowIndex(value) {
                index += 1
                return Self.rows(first, try rowEnd(), sheet: nil)
            }
            return .number(value)
        case .leftBrace:
            return try arrayConstant()
        case .text(let text):
            return .text(text)
        case .error(let error):
            return .error(error)
        case .leftParen:
            let expr = try comparison()
            guard case .rightParen = try next() else { throw FormulaSyntaxError() }
            return expr
        case .sheet(let sheet):
            // 'Jan:Mar'!A1 names a span of sheets.
            let span = sheet.split(separator: ":", maxSplits: 1).map(String.init)
            switch try next() {
            case .word(let word):
                let target = try reference(word, sheet: span.count == 2 ? nil : sheet)
                guard span.count == 2 else { return target }
                return .sheetSpan(first: span[0], last: span[1], try Self.area(of: target))
            case .number(let value):
                guard case .colon? = peek, let first = Self.rowIndex(value) else { throw FormulaSyntaxError() }
                index += 1
                return Self.rows(first, try rowEnd(), sheet: sheet)
            default:
                throw FormulaSyntaxError()
            }
        case .word(let word):
            if case .leftParen? = peek {
                index += 1
                return .call(FormulaText.functionName(word), try arguments())
            }
            switch word.uppercased() {
            case "TRUE": return .boolean(true)
            case "FALSE": return .boolean(false)
            default: return try reference(word, sheet: nil)
            }
        default:
            throw FormulaSyntaxError()
        }
    }

    private mutating func arguments() throws -> [Expr] {
        if case .rightParen? = peek {
            index += 1
            return []
        }
        var args: [Expr] = []
        while true {
            switch peek {
            case .comma?, .rightParen?: args.append(.missing)
            default: args.append(try comparison())
            }
            switch try next() {
            case .comma: continue
            case .rightParen: return args
            default: throw FormulaSyntaxError()
            }
        }
    }

    private mutating func rangeEnd() throws -> String {
        if case .sheet? = peek { index += 1 }
        guard case .word(let word) = try next() else { throw FormulaSyntaxError() }
        return word
    }

    private mutating func reference(_ word: String, sheet: String?) throws -> Expr {
        // A 3D reference such as Sheet1:Sheet3!A1. A cell first (A1:Sheet1!B2) is an ordinary range.
        if sheet == nil, A1Reference.parse(word) == nil, case .colon? = peek, index + 1 < tokens.count,
           case .sheet(let last) = tokens[index + 1].kind {
            index += 2
            guard case .word(let target) = try next() else { throw FormulaSyntaxError() }
            return .sheetSpan(first: word, last: last, try Self.area(of: try reference(target, sheet: nil)))
        }
        if let start = A1Reference.parse(word) {
            guard case .colon? = peek else { return .reference(sheet: sheet, start.address) }
            index += 1
            guard let end = A1Reference.parse(try rangeEnd()) else { throw CellError.reference }
            return .range(sheet: sheet, CellRange(start.address, end.address))
        }
        if let start = A1Reference.parseColumn(word), case .colon? = peek {
            index += 1
            guard let end = A1Reference.parseColumn(try rangeEnd()) else { throw CellError.reference }
            return .range(sheet: sheet, CellRange(
                CellAddress(row: 0, column: start.column),
                CellAddress(row: CellAddress.maxRows - 1, column: end.column)
            ))
        }
        if let first = A1Reference.parseRow(word), case .colon? = peek {
            index += 1
            return Self.rows(first, try rowEnd(), sheet: sheet)
        }
        guard sheet == nil else { throw CellError.name }
        return .name(word)
    }

    private mutating func rowEnd() throws -> Int {
        if case .sheet? = peek { index += 1 }
        switch try next() {
        case .number(let value):
            guard let row = Self.rowIndex(value) else { throw CellError.reference }
            return row
        case .word(let word):
            guard let row = A1Reference.parseRow(word) else { throw CellError.reference }
            return row
        default:
            throw FormulaSyntaxError()
        }
    }

    private mutating func arrayConstant() throws -> Expr {
        var rows: [[CellValue]] = [[]]
        while true {
            var sign = 1.0
            if case .op("-")? = peek {
                index += 1
                sign = -1
            }
            let value: CellValue
            switch try next() {
            case .number(let n): value = .number(sign * n)
            case .text(let text): value = .text(text)
            case .error(let error): value = .error(error)
            case .word(let word) where ["TRUE", "FALSE"].contains(word.uppercased()): value = .boolean(word.uppercased() == "TRUE")
            default: throw FormulaSyntaxError()
            }
            rows[rows.count - 1].append(value)
            switch try next() {
            case .comma: continue
            case .semicolon: rows.append([])
            case .rightBrace: return .array(rows)
            default: throw FormulaSyntaxError()
            }
        }
    }

    /// Zero-based row for a row number written in a formula.
    static func rowIndex(_ value: Double) -> Int? {
        value >= 1 && value <= Double(CellAddress.maxRows) && value == value.rounded() ? Int(value) - 1 : nil
    }

    private static func rows(_ first: Int, _ last: Int, sheet: String?) -> Expr {
        .range(sheet: sheet, CellRange(CellAddress(row: first, column: 0), CellAddress(row: last, column: CellAddress.maxColumns - 1)))
    }

    private static func area(of expr: Expr) throws -> CellRange {
        switch expr {
        case .reference(_, let address): return CellRange(address, address)
        case .range(_, let range): return range
        default: throw CellError.reference
        }
    }
}

/// Edits formula text token by token, leaving everything else as typed.
public enum FormulaText {
    /// Excel 2010+ functions are stored in files with a `_xlfn.` prefix.
    static let prefixedFunctions: Set<String> = [
        "CONCAT", "DAYS", "IFS", "MAXIFS", "MINIFS", "RANK.EQ", "STDEV.P", "STDEV.S", "SWITCH", "TEXTJOIN",
        "VAR.P", "VAR.S", "XLOOKUP",
    ]

    static func functionName(_ word: String) -> String {
        var name = word.uppercased()
        for prefix in ["_XLFN.", "_XLWS."] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }
        return name
    }

    /// Moves relative references by an offset, as Excel does when a formula is copied.
    /// References pushed off the sheet become `#REF!`.
    public static func shifted(_ raw: String, rows: Int, columns: Int) -> String {
        guard rows != 0 || columns != 0 else { return raw }
        return rewrite(raw) { tokens, index in
            if case .number(let value) = tokens[index].kind, isAdjacentToColon(tokens, index), let row = FormulaParser.rowIndex(value) {
                let moved = row + rows
                return moved >= 0 && moved < CellAddress.maxRows ? String(moved + 1) : CellError.reference.rawValue
            }
            guard case .word(let word) = tokens[index].kind, !isFunctionCall(tokens, index) else { return nil }
            if var reference = A1Reference.parse(word) {
                if !reference.absoluteRow { reference.address.row += rows }
                if !reference.absoluteColumn { reference.address.column += columns }
                return reference.address.isValid ? reference.formatted() : CellError.reference.rawValue
            }
            if isAdjacentToColon(tokens, index), let column = A1Reference.parseColumn(word), !column.absolute {
                let shifted = column.column + columns
                guard shifted >= 0, shifted < CellAddress.maxColumns else { return CellError.reference.rawValue }
                return CellAddress.columnName(shifted)
            }
            return nil
        } ?? raw
    }

    /// Uppercases names and references and closes open parentheses, as Excel does on entry.
    public static func normalized(_ raw: String) -> String {
        guard CellInput.isFormula(raw) else { return raw }
        var depth = 0
        let rewritten = rewrite(raw) { tokens, index in
            switch tokens[index].kind {
            case .leftParen: depth += 1
            case .rightParen: depth -= 1
            case .word(let word): return word.uppercased()
            default: break
            }
            return nil
        }
        guard let rewritten else { return raw }
        return rewritten + String(repeating: ")", count: max(depth, 0))
    }

    /// Formula text as stored in an XLSX `<f>` element: no `=`, newer functions prefixed.
    static func fileForm(_ raw: String) -> String {
        let body = rewrite(raw) { tokens, index in
            guard case .word(let word) = tokens[index].kind, isFunctionCall(tokens, index) else { return nil }
            let name = functionName(word)
            return prefixedFunctions.contains(name) ? "_xlfn." + name : nil
        } ?? raw
        return String(body.dropFirst())
    }

    /// Cell input for the text of an XLSX `<f>` element, without file-only prefixes.
    static func fromFileForm(_ text: String) -> String {
        let raw = "=" + text
        let unprefixed = rewrite(raw) { tokens, index in
            guard case .word(let word) = tokens[index].kind, isFunctionCall(tokens, index) else { return nil }
            let name = functionName(word)
            return name == word.uppercased() ? nil : name
        } ?? raw
        return normalized(unprefixed)
    }

    /// Rewrites tokens of a formula; returns nil if it does not tokenize.
    static func rewrite(_ raw: String, _ transform: ([FormulaToken], Int) -> String?) -> String? {
        let chars = Array(raw)
        guard chars.first == "=", let tokens = try? FormulaLexer.tokenize(chars, from: 1) else { return nil }
        var output = ""
        var position = 0
        for index in tokens.indices {
            let token = tokens[index]
            guard let replacement = transform(tokens, index) else { continue }
            output += String(chars[position..<token.range.lowerBound]) + replacement
            position = token.range.upperBound
        }
        return output + String(chars[position...])
    }

    /// Updates references after rows or columns of `targetSheet` were inserted or deleted.
    /// References into deleted cells become `#REF!`; ranges shrink or grow like Excel's.
    static func adjusted(_ raw: String, for change: StructuralChange, targetSheet: String, formulaSheet: String) -> String {
        let chars = Array(raw)
        guard chars.first == "=", let tokens = try? FormulaLexer.tokenize(chars, from: 1) else { return raw }
        var replacements: [Int: String] = [:]

        func qualifier(_ index: Int) -> (sheet: String, tokenIndex: Int?) {
            if index > 0, case .sheet(let name) = tokens[index - 1].kind { return (name, index - 1) }
            return (formulaSheet, nil)
        }

        var i = 0
        while i < tokens.count {
            guard case .word(let word) = tokens[i].kind, !isFunctionCall(tokens, i) else {
                i += 1
                continue
            }
            let (sheet, sheetToken) = qualifier(i)
            let applies = sheet.caseInsensitiveCompare(targetSheet) == .orderedSame

            // A range: word, colon, optional sheet, word.
            if i + 2 < tokens.count, tokens[i + 1].kind == .colon {
                var end = i + 2
                if case .sheet = tokens[end].kind { end += 1 }
                if end < tokens.count, case .word(let endWord) = tokens[end].kind {
                    if applies {
                        if let moved = change.adjustRange(word, endWord) {
                            replacements[i] = moved.start
                            replacements[end] = moved.end
                        } else {
                            if let sheetToken { replacements[sheetToken] = "" }
                            replacements[i] = CellError.reference.rawValue
                            for index in (i + 1)...end { replacements[index] = "" }
                        }
                    }
                    i = end + 1
                    continue
                }
            }
            if applies, let reference = A1Reference.parse(word) {
                if let moved = change.adjust(reference) {
                    replacements[i] = moved.formatted()
                } else {
                    if let sheetToken { replacements[sheetToken] = "" }
                    replacements[i] = CellError.reference.rawValue
                }
            }
            i += 1
        }
        guard !replacements.isEmpty else { return raw }
        return rewrite(raw) { _, index in replacements[index] } ?? raw
    }

    static func isFunctionCall(_ tokens: [FormulaToken], _ index: Int) -> Bool {
        index + 1 < tokens.count && tokens[index + 1].kind == .leftParen
    }

    private static func isAdjacentToColon(_ tokens: [FormulaToken], _ index: Int) -> Bool {
        (index + 1 < tokens.count && tokens[index + 1].kind == .colon)
            || (index > 0 && tokens[index - 1].kind == .colon)
    }
}
