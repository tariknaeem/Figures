import Foundation

/// Evaluates one immutable workbook snapshot, caching each computed cell.
public final class Calculator {
    public let workbook: Workbook

    struct Key: Hashable {
        let sheet: Int
        let address: CellAddress
    }

    enum Operand {
        case value(CellValue)
        case range(sheet: Int, CellRange)
        /// An array constant, flattened row by row.
        case values([CellValue])
        /// The same area on several sheets, from a 3D reference.
        case areas([(sheet: Int, range: CellRange)])
    }

    /// Deeper dependency chains report #NUM! instead of exhausting the stack.
    private static let maxDepth = 1_000

    private var cache: [Key: CellValue] = [:]
    private var inProgress: Set<Key> = []
    private var evaluationStack: [Key] = []

    /// The formula cell being evaluated, for ROW() and COLUMN() without arguments.
    var currentCell: CellAddress? { evaluationStack.last?.address }
    private var parsed: [String: Result<Expr, CellError>] = [:]
    var conditionalCache: [Key: ConditionalResult] = [:]
    private var nameDepth = 0
    var conditionalStats: [String: ConditionalStats] = [:]

    public init(workbook: Workbook) {
        self.workbook = workbook
    }

    /// Evaluates formula text (starting with `=`) as if it were entered in `address`, without storing it.
    public func evaluate(formula raw: String, sheet: Int, at address: CellAddress) -> CellValue {
        evaluationStack.append(Key(sheet: sheet, address: address))
        defer { evaluationStack.removeLast() }
        switch formula(raw) {
        case .success(let expr): return scalar(expr, sheet)
        case .failure(let error): return .error(error)
        }
    }

    public func value(sheet: Int, at address: CellAddress) -> CellValue {
        let key = Key(sheet: sheet, address: address)
        if let cached = cache[key] { return cached }
        guard workbook.sheets.indices.contains(sheet), let raw = workbook.sheets[sheet].cells[address] else {
            return .empty
        }
        guard CellInput.isFormula(raw) else {
            let literal = CellInput.literalValue(raw)
            cache[key] = literal
            return literal
        }
        if inProgress.contains(key) { return .error(.circular) }
        if inProgress.count >= Self.maxDepth { return .error(.number) }

        inProgress.insert(key)
        evaluationStack.append(key)
        let result: CellValue
        switch formula(raw) {
        case .success(let expr): result = scalar(expr, sheet)
        case .failure(let error): result = .error(error)
        }
        evaluationStack.removeLast()
        inProgress.remove(key)

        // A formula that refers to an empty cell shows 0, as in Excel.
        let computed = result == .empty ? .number(0) : result
        cache[key] = computed
        return computed
    }

    /// The display text of a cell with its number format applied.
    public func displayText(sheet: Int, at address: CellAddress) -> String {
        let format = workbook.sheets.indices.contains(sheet) ? workbook.sheets[sheet].formats[address] : nil
        return value(sheet: sheet, at: address).formatted(format)
    }

    /// Rows hidden by the user plus data rows the AutoFilter excludes.
    public func hiddenRows(sheet index: Int) -> Set<Int> {
        guard workbook.sheets.indices.contains(index) else { return [] }
        let sheet = workbook.sheets[index]
        var hidden = sheet.hiddenRows
        guard let filter = sheet.filter, !filter.allowedValues.isEmpty, let rows = filter.dataRows else { return hidden }
        for row in rows {
            for (column, allowed) in filter.allowedValues
            where !allowed.contains(displayText(sheet: index, at: CellAddress(row: row, column: column))) {
                hidden.insert(row)
                break
            }
        }
        return hidden
    }

    /// The next cell after `start` (row by row, wrapping) whose shown text or formula contains `query`.
    public func find(_ query: String, sheet index: Int, after start: CellAddress, matchCase: Bool) -> CellAddress? {
        guard !query.isEmpty, workbook.sheets.indices.contains(index) else { return nil }
        let options: String.CompareOptions = matchCase ? [] : [.caseInsensitive]
        let sheet = workbook.sheets[index]
        let candidates = sheet.cells.keys.sorted()
        let ordered = candidates.filter { $0 > start } + candidates.filter { $0 <= start }
        return ordered.first { address in
            displayText(sheet: index, at: address).range(of: query, options: options) != nil
                || (sheet.cells[address]?.range(of: query, options: options) != nil)
        }
    }

    /// Non-empty cells of a range in row-major order.
    public func cells(in range: CellRange, sheet: Int) -> [(address: CellAddress, value: CellValue)] {
        guard workbook.sheets.indices.contains(sheet) else { return [] }
        let stored = workbook.sheets[sheet].cells
        let addresses = range.cellCount <= stored.count
            ? range.addresses.filter { stored[$0] != nil }
            : stored.keys.filter(range.contains).sorted()
        return addresses.compactMap { address in
            let value = value(sheet: sheet, at: address)
            return value == .empty ? nil : (address, value)
        }
    }

    func formula(_ raw: String) -> Result<Expr, CellError> {
        if let cached = parsed[raw] { return cached }
        let result = FormulaParser.parse(raw)
        parsed[raw] = result
        return result
    }

    func resolveSheet(_ name: String?, from sheet: Int) -> Int? {
        guard let name else { return sheet }
        return workbook.sheetIndex(named: name)
    }

    func evaluate(_ expr: Expr, _ sheet: Int) -> Operand {
        switch expr {
        case .number(let n): return .value(.number(n))
        case .text(let s): return .value(.text(s))
        case .boolean(let b): return .value(.boolean(b))
        case .error(let e): return .value(.error(e))
        case .reference(let name, let address):
            guard let target = resolveSheet(name, from: sheet) else { return .value(.error(.reference)) }
            return .range(sheet: target, CellRange(address, address))
        case .range(let name, let range):
            guard let target = resolveSheet(name, from: sheet) else { return .value(.error(.reference)) }
            return .range(sheet: target, range)
        case .negate(let inner):
            let operand = scalar(inner, sheet)
            return .value(Self.numeric { -(try Self.number(operand)) })
        case .percent(let inner):
            let operand = scalar(inner, sheet)
            return .value(Self.numeric { try Self.number(operand) / 100 })
        case .binary(let op, let lhs, let rhs):
            return .value(binary(op, scalar(lhs, sheet), scalar(rhs, sheet)))
        case .call(let name, let args):
            if name == "INDIRECT" || name == "OFFSET" { return referenceFunction(name, args, sheet) }
            return .value(call(name, args, sheet))
        case .name(let name):
            return definedName(name, sheet)
        case .missing:
            return .value(.empty)
        case .array(let rows):
            return .values(rows.flatMap { $0 })
        case .sheetSpan(let first, let last, let range):
            guard let a = workbook.sheetIndex(named: first), let b = workbook.sheetIndex(named: last) else {
                return .value(.error(.reference))
            }
            return .areas((min(a, b)...max(a, b)).map { ($0, range) })
        }
    }

    /// A defined name's value: a sheet-scoped definition wins over a workbook-wide one.
    private func definedName(_ name: String, _ sheet: Int) -> Operand {
        let matches = workbook.definedNames.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        guard let definition = matches.first(where: { $0.scope == sheet }) ?? matches.first(where: { $0.scope == nil }) else {
            return .value(.error(.name))
        }
        guard nameDepth < 32 else { return .value(.error(.circular)) }
        nameDepth += 1
        defer { nameDepth -= 1 }
        switch formula("=" + definition.formula) {
        case .success(let expr): return evaluate(expr, sheet)
        case .failure(let error): return .value(.error(error))
        }
    }

    func scalar(_ expr: Expr, _ sheet: Int) -> CellValue {
        switch evaluate(expr, sheet) {
        case .value(let value):
            return value
        case .range(let target, let range):
            // Multi-cell ranges are only meaningful as function arguments.
            return range.cellCount == 1 ? value(sheet: target, at: range.start) : .error(.value)
        case .values(let values):
            return values.first ?? .empty
        case .areas:
            return .error(.value)
        }
    }

    private func binary(_ op: BinaryOperator, _ lhs: CellValue, _ rhs: CellValue) -> CellValue {
        if case .error(let e) = lhs { return .error(e) }
        if case .error(let e) = rhs { return .error(e) }
        switch op {
        case .add: return Self.numeric { try Self.number(lhs) + Self.number(rhs) }
        case .subtract: return Self.numeric { try Self.number(lhs) - Self.number(rhs) }
        case .multiply: return Self.numeric { try Self.number(lhs) * Self.number(rhs) }
        case .divide:
            return Self.numeric {
                let numerator = try Self.number(lhs)
                let denominator = try Self.number(rhs)
                guard denominator != 0 else { throw CellError.divideByZero }
                return numerator / denominator
            }
        case .power: return Self.numeric { pow(try Self.number(lhs), try Self.number(rhs)) }
        case .concat: return .text(lhs.displayText + rhs.displayText)
        case .equal: return .boolean(Self.compare(lhs, rhs) == 0)
        case .notEqual: return .boolean(Self.compare(lhs, rhs) != 0)
        case .less: return .boolean(Self.compare(lhs, rhs) < 0)
        case .lessOrEqual: return .boolean(Self.compare(lhs, rhs) <= 0)
        case .greater: return .boolean(Self.compare(lhs, rhs) > 0)
        case .greaterOrEqual: return .boolean(Self.compare(lhs, rhs) >= 0)
        }
    }

    // MARK: - Coercion

    static func numeric(_ body: () throws -> Double) -> CellValue {
        do {
            let result = try body()
            return result.isFinite ? .number(result) : .error(.number)
        } catch let error as CellError {
            return .error(error)
        } catch {
            return .error(.value)
        }
    }

    static func number(_ value: CellValue) throws -> Double {
        switch value {
        case .empty: return 0
        case .number(let n): return n
        case .boolean(let b): return b ? 1 : 0
        case .text(let s):
            guard let n = CellInput.parseNumber(s.trimmingCharacters(in: .whitespaces)) else { throw CellError.value }
            return n
        case .error(let e): throw e
        }
    }

    static func boolean(_ value: CellValue) throws -> Bool {
        switch value {
        case .empty: return false
        case .number(let n): return n != 0
        case .boolean(let b): return b
        case .text(let s):
            switch s.uppercased() {
            case "TRUE": return true
            case "FALSE": return false
            default: throw CellError.value
            }
        case .error(let e): throw e
        }
    }

    static func text(_ value: CellValue) throws -> String {
        if case .error(let e) = value { throw e }
        return value.displayText
    }

    /// Excel ordering: numbers < text < FALSE < TRUE; text compares case-insensitively.
    /// An empty cell compares as 0, "" or FALSE depending on the other side.
    static func compare(_ lhs: CellValue, _ rhs: CellValue) -> Int {
        let a = emptyAsKind(lhs, of: rhs)
        let b = emptyAsKind(rhs, of: lhs)
        let (ra, rb) = (rank(a), rank(b))
        if ra != rb { return ra < rb ? -1 : 1 }
        switch (a, b) {
        case (.number(let x), .number(let y)):
            return x == y ? 0 : (x < y ? -1 : 1)
        case (.text(let x), .text(let y)):
            switch x.caseInsensitiveCompare(y) {
            case .orderedAscending: return -1
            case .orderedSame: return 0
            case .orderedDescending: return 1
            }
        case (.boolean(let x), .boolean(let y)):
            return x == y ? 0 : (!x ? -1 : 1)
        default:
            return 0
        }
    }

    /// Excel's ascending sort order, for use as a `sorted(by:)` predicate.
    public static func compareForSort(_ lhs: CellValue, _ rhs: CellValue) -> Bool {
        compare(lhs, rhs) < 0
    }

    static func rank(_ value: CellValue) -> Int {
        switch value {
        case .empty, .number: 0
        case .text: 1
        case .boolean: 2
        case .error: 3
        }
    }

    private static func emptyAsKind(_ value: CellValue, of other: CellValue) -> CellValue {
        guard value == .empty else { return value }
        switch other {
        case .text: return .text("")
        case .boolean: return .boolean(false)
        default: return .number(0)
        }
    }
}
