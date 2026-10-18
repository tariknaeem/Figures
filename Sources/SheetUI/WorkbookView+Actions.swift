import SheetCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum PasteSpecial {
    case values, formulas, formats, transpose
}

extension WorkbookView {
    // MARK: - Keyboard and pointer

    var isShiftPressed: Bool {
        #if os(macOS)
        NSEvent.modifierFlags.contains(.shift)
        #else
        false
        #endif
    }

    private func isPrintable(_ characters: String) -> Bool {
        !characters.isEmpty && characters.unicodeScalars.allSatisfy { scalar in
            // AppKit reports arrow and function keys in the private-use area.
            !CharacterSet.controlCharacters.contains(scalar) && !(0xF700...0xF8FF).contains(scalar.value)
        }
    }

    func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let plain = press.modifiers.isDisjoint(with: [.command, .control, .option])
        if editor != nil {
            // Keys typed before the cell's text field takes focus.
            guard focus == .grid, plain, isPrintable(press.characters) else { return .ignored }
            editor?.text += press.characters
            return .handled
        }
        let extend = press.modifiers.contains(.shift)
        switch press.key {
        case .upArrow: move(rows: -1, columns: 0, extend: extend)
        case .downArrow: move(rows: 1, columns: 0, extend: extend)
        case .leftArrow: move(rows: 0, columns: -1, extend: extend)
        case .rightArrow: move(rows: 0, columns: 1, extend: extend)
        case .return: move(rows: extend ? -1 : 1, columns: 0, extend: false)
        case .tab: move(rows: 0, columns: extend ? -1 : 1, extend: false)
        case .delete, .deleteForward: clearSelection()
        case .escape:
            model.findVisible = false
            model.painter = nil
        default:
            #if os(iOS)
            if press.modifiers.contains(.command) { return handleCommandKey(press.characters) }
            #endif
            guard plain, isPrintable(press.characters) else { return .ignored }
            beginEditing(at: selection.active, text: press.characters)
        }
        return .handled
    }

    #if os(iOS)
    private func handleCommandKey(_ characters: String) -> KeyPress.Result {
        switch characters.lowercased() {
        case "c": _ = copySelection()
        case "x": _ = cutSelection()
        case "v": pasteFromSystem()
        case "z": undoManager?.undo()
        default: return .ignored
        }
        return .handled
    }
    #endif

    /// Moves the active cell, stepping over hidden rows and columns and whole merged areas.
    func move(rows: Int, columns: Int, extend: Bool) {
        let hidden = calculator.hiddenRows(sheet: activeSheet)
        var origin = selection.active
        if !extend, let merge = sheet.merge(containing: origin) {
            if rows > 0 { origin.row = merge.end.row }
            if columns > 0 { origin.column = merge.end.column }
        }
        var target = origin.offset(rows: rows, columns: columns).clamped()
        let rowStep = rows < 0 ? -1 : 1
        while rows != 0, hidden.contains(target.row), target.row + rowStep >= 0, target.row + rowStep < CellAddress.maxRows {
            target.row += rowStep
        }
        let columnStep = columns < 0 ? -1 : 1
        while columns != 0, sheet.hiddenColumns.contains(target.column), target.column + columnStep >= 0,
              target.column + columnStep < CellAddress.maxColumns {
            target.column += columnStep
        }
        if extend {
            selection.active = target
        } else {
            select(target)
        }
    }

    /// Selects a cell, or the whole merged area it belongs to.
    func select(_ address: CellAddress) {
        if let merge = sheet.merge(containing: address) {
            selection = GridSelection(anchor: merge.end, active: merge.start)
        } else {
            selection = GridSelection(address)
        }
    }

    func cellTapped(_ tapped: CellAddress) {
        let address = sheet.merge(containing: tapped)?.start ?? tapped
        // While typing a formula, clicking a cell inserts its reference.
        if var current = editor, current.text.hasPrefix("="), current.address != address,
           let last = current.text.last, "=(,+-*/^&<>:".contains(last) {
            current.text += address.a1
            editor = current
            focusEditor(current)
            return
        }
        commitEdit(moveRows: 0, moveColumns: 0)
        let now = Date()
        if let lastTap = model.lastTap, lastTap.address == address, now.timeIntervalSince(lastTap.time) < 0.4, !isShiftPressed {
            model.lastTap = nil
            beginEditing(at: address, text: nil)
            return
        }
        model.lastTap = (address, now)
        if isShiftPressed {
            selection.active = address
        } else {
            select(address)
        }
        if let painter = model.painter {
            model.painter = nil
            updateFormats("Format Painter") { $0 = painter }
        }
        focus = .grid
    }

    private var lastUsedRow: Int { max(sheet.maxRow ?? 0, 0) }
    private var lastUsedColumn: Int { max(sheet.maxColumn ?? 0, 0) }

    /// Selects a column down to the last used row; the active cell stays at the top.
    func selectColumn(_ column: Int) {
        commitEdit(moveRows: 0, moveColumns: 0)
        selection = GridSelection(anchor: CellAddress(row: lastUsedRow, column: column), active: CellAddress(row: 0, column: column))
        focus = .grid
    }

    func selectRow(_ row: Int) {
        commitEdit(moveRows: 0, moveColumns: 0)
        selection = GridSelection(anchor: CellAddress(row: row, column: lastUsedColumn), active: CellAddress(row: row, column: 0))
        focus = .grid
    }

    func selectAll() {
        commitEdit(moveRows: 0, moveColumns: 0)
        selection = GridSelection(anchor: CellAddress(row: lastUsedRow, column: lastUsedColumn), active: CellAddress(row: 0, column: 0))
        focus = .grid
    }

    /// Jumps to the cell, range or defined name typed into the name box.
    func goToNameBox() {
        let text = (model.nameBox ?? "").trimmingCharacters(in: .whitespaces)
        model.nameBox = nil
        let ends = text.split(separator: ":").map(String.init)
        if let first = ends.first.flatMap({ CellAddress(a1: $0) }) {
            let last = ends.count > 1 ? CellAddress(a1: ends[1]) ?? first : first
            selection = GridSelection(anchor: last, active: first)
        } else if let name = workbook.definedNames.first(where: { $0.name.caseInsensitiveCompare(text) == .orderedSame }),
                  let target = definedNameTarget(name) {
            if target.sheet != activeSheet { switchSheet(target.sheet) }
            selection = GridSelection(anchor: target.range.end, active: target.range.start)
        } else if !text.isEmpty {
            model.message = "“\(text)” is not a cell reference or name. Type something like B12 or A1:C10."
        }
        focus = .grid
    }

    /// Where a defined name points, when it names a single area such as `Sheet1!$A$1:$B$5`.
    private func definedNameTarget(_ name: DefinedName) -> (sheet: Int, range: CellRange)? {
        let text = name.formula.replacingOccurrences(of: "$", with: "")
        let parts = text.split(separator: "!", maxSplits: 1).map(String.init)
        let sheetName = parts.count == 2 ? parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "'")) : nil
        let reference = parts.count == 2 ? parts[1] : parts[0]
        guard let index = sheetName.map({ workbook.sheetIndex(named: $0) }) ?? activeSheet else { return nil }
        let ends = reference.split(separator: ":").map(String.init)
        guard let start = ends.first.flatMap({ CellAddress(a1: $0) }) else { return nil }
        return (index, CellRange(start, ends.count > 1 ? CellAddress(a1: ends[1]) ?? start : start))
    }

    // MARK: - Editing

    func beginEditing(at address: CellAddress, text: String?) {
        select(address)
        let current = CellEditor(address: address, text: text ?? sheet.cells[address] ?? "", inCell: true)
        editor = current
        focusEditor(current)
    }

    func focusEditor(_ current: CellEditor) {
        // The text field exists only after this update, so focus it on the next pass.
        DispatchQueue.main.async {
            focus = current.inCell ? .cellEditor : .formulaBar
            DispatchQueue.main.async { moveCaretToEnd() }
        }
    }

    /// AppKit selects all text when a field gains focus; Excel keeps typing at the end.
    private func moveCaretToEnd() {
        #if os(macOS)
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.moveToEndOfDocument(nil)
        #endif
    }

    func acceptSuggestion(_ name: String, replacing prefix: String) {
        guard var current = editor else { return }
        current.text = String(current.text.dropLast(prefix.count)) + name + "("
        editor = current
        focusEditor(current)
    }

    /// Adds a function to the formula being typed, or starts a new formula with it.
    func insertFunction(_ name: String) {
        if var current = editor {
            current.text += (current.text.isEmpty ? "=" : "") + name + "("
            editor = current
            focusEditor(current)
        } else {
            beginEditing(at: selection.active, text: "=" + name + "(")
        }
    }

    func commitEdit(moveRows: Int, moveColumns: Int) {
        guard let current = editor else { return }
        editor = nil
        let text = FormulaText.normalized(current.text)
        if text != (sheet.cells[current.address] ?? "") {
            let index = activeSheet
            mutate("Typing") { $0.sheets[index].setInput(text, at: current.address) }
        }
        if moveRows == 0 && moveColumns == 0 {
            select(current.address)
        } else {
            selection = GridSelection(current.address)
            move(rows: moveRows, columns: moveColumns, extend: false)
        }
        focus = .grid
    }

    func cancelEdit() {
        if let current = editor {
            editor = nil
            select(current.address)
        }
        focus = .grid
    }

    /// Enters today's date (⌘;) or the current time (⇧⌘;) as a value, like Excel.
    func insertNow(time: Bool) {
        commitEdit(moveRows: 0, moveColumns: 0)
        let now = Date()
        let local = now.timeIntervalSince1970 + Double(TimeZone.current.secondsFromGMT(for: now))
        let serial = local / 86_400 + 25_569
        let value = time ? serial - serial.rounded(.down) : serial.rounded(.down)
        let address = selection.active
        let index = activeSheet
        mutate(time ? "Insert Time" : "Insert Date") { workbook in
            workbook.sheets[index].setInput(CellInput.rawInput(for: .number(value)), at: address)
            var format = workbook.sheets[index].formats[address] ?? CellFormat()
            format.numberFormat = time ? "h:mm AM/PM" : "m/d/yyyy"
            workbook.sheets[index].setFormat(format, at: address)
        }
    }

    /// Applies a change as one undoable step.
    func mutate(_ actionName: String, _ change: (inout Workbook) -> Void) {
        let before = workbook
        change(&workbook)
        guard let undoManager, before != workbook else { return }
        Self.registerUndo(undoManager, target: model.undoTarget, workbook: $workbook, restoring: before, actionName: actionName)
    }

    private static func registerUndo(
        _ manager: UndoManager,
        target: UndoTarget,
        workbook: Binding<Workbook>,
        restoring snapshot: Workbook,
        actionName: String
    ) {
        manager.registerUndo(withTarget: target) { target in
            let current = workbook.wrappedValue
            workbook.wrappedValue = snapshot
            // Registering during an undo records the redo step.
            registerUndo(manager, target: target, workbook: workbook, restoring: current, actionName: actionName)
        }
        manager.setActionName(actionName)
    }

    /// Addresses in a range that hold input, without walking huge empty selections.
    func storedAddresses(in range: CellRange) -> [CellAddress] {
        range.cellCount <= sheet.cells.count
            ? range.addresses.filter { sheet.cells[$0] != nil }
            : sheet.cells.keys.filter(range.contains)
    }

    func clearSelection() {
        let index = activeSheet
        let targets = storedAddresses(in: selection.range)
        guard !targets.isEmpty else { return }
        mutate("Clear Contents") { workbook in
            for address in targets { workbook.sheets[index].setInput("", at: address) }
        }
    }

    func clearFormats() {
        let index = activeSheet
        let range = selection.range
        mutate("Clear Formats") { workbook in
            for address in workbook.sheets[index].formats.keys where range.contains(address) {
                workbook.sheets[index].formats.removeValue(forKey: address)
            }
        }
    }

    func clearAll() {
        let index = activeSheet
        let range = selection.range
        let targets = storedAddresses(in: range)
        mutate("Clear All") { workbook in
            for address in targets { workbook.sheets[index].setInput("", at: address) }
            for address in workbook.sheets[index].formats.keys where range.contains(address) {
                workbook.sheets[index].formats.removeValue(forKey: address)
            }
        }
    }

    // MARK: - Clipboard

    @discardableResult
    func copySelection() -> [NSItemProvider] {
        let range = selection.range
        let calc = calculator
        var inputs: [[String]] = []
        var values: [[String]] = []
        var formats: [[CellFormat?]] = []
        var shown: [[String]] = []
        for row in range.start.row...range.end.row {
            let addresses = (range.start.column...range.end.column).map { CellAddress(row: row, column: $0) }
            inputs.append(addresses.map { sheet.cells[$0] ?? "" })
            values.append(addresses.map { CellInput.rawInput(for: calc.value(sheet: activeSheet, at: $0)) })
            formats.append(addresses.map { sheet.formats[$0] })
            shown.append(addresses.map { calc.displayText(sheet: activeSheet, at: $0) })
        }
        let text = CSV.encode(shown, delimiter: "\t")
        model.clipboard = GridClipboard(origin: range.start, inputs: inputs, values: values, formats: formats, text: text)
        #if os(iOS)
        UIPasteboard.general.string = text
        #endif
        return [NSItemProvider(object: text as NSString)]
    }

    func cutSelection() -> [NSItemProvider] {
        let providers = copySelection()
        clearSelection()
        return providers
    }

    func pasteFromSystem() {
        #if os(macOS)
        let text = NSPasteboard.general.string(forType: .string)
        #else
        let text = UIPasteboard.general.string
        #endif
        if let text { paste(text) }
    }

    /// Pastes at the top-left of the selection. Cells copied here keep formulas, moved
    /// by the paste offset; text from other apps is read as tab-separated values.
    func paste(_ text: String) {
        commitEdit(moveRows: 0, moveColumns: 0)
        let origin = selection.range.start
        if let clipboard = model.clipboard, clipboard.text == text {
            let rows = origin.row - clipboard.origin.row
            let columns = origin.column - clipboard.origin.column
            let inputs = clipboard.inputs.map { row in
                row.map { CellInput.isFormula($0) ? FormulaText.shifted($0, rows: rows, columns: columns) : $0 }
            }
            write(inputs: inputs, formats: clipboard.formats, at: origin, actionName: "Paste")
        } else {
            write(inputs: CSV.rows(text, delimiter: "\t"), formats: nil, at: origin, actionName: "Paste")
        }
    }

    /// Paste Values, Formulas, Formatting or Transpose from cells copied in this window.
    func pasteSpecial(_ kind: PasteSpecial) {
        guard let clipboard = model.clipboard else {
            model.message = "Copy cells in Figures first; Paste Special works with cells copied here."
            return
        }
        commitEdit(moveRows: 0, moveColumns: 0)
        let origin = selection.range.start
        let rows = origin.row - clipboard.origin.row
        let columns = origin.column - clipboard.origin.column
        switch kind {
        case .values:
            write(inputs: clipboard.values, formats: nil, at: origin, actionName: "Paste Values")
        case .formulas:
            let inputs = clipboard.inputs.map { $0.map { CellInput.isFormula($0) ? FormulaText.shifted($0, rows: rows, columns: columns) : $0 } }
            write(inputs: inputs, formats: nil, at: origin, actionName: "Paste Formulas")
        case .formats:
            write(inputs: nil, formats: clipboard.formats, at: origin, actionName: "Paste Formatting")
        case .transpose:
            let height = clipboard.inputs.count
            let width = clipboard.inputs.first?.count ?? 0
            let inputs = (0..<width).map { c in (0..<height).map { r in clipboard.values[r][c] } }
            let formats = (0..<width).map { c in (0..<height).map { r in clipboard.formats[r][c] } }
            write(inputs: inputs, formats: formats, at: origin, actionName: "Paste Transposed")
        }
    }

    private func write(inputs: [[String]]?, formats: [[CellFormat?]]?, at origin: CellAddress, actionName: String) {
        let grid = inputs ?? formats.map { $0.map { $0.map { _ in "" } } } ?? []
        guard !grid.isEmpty else { return }
        let index = activeSheet
        mutate(actionName) { workbook in
            for r in grid.indices {
                for c in grid[r].indices {
                    let address = origin.offset(rows: r, columns: c)
                    guard address.isValid else { continue }
                    if let inputs { workbook.sheets[index].setInput(inputs[r][c], at: address) }
                    if let formats, r < formats.count, c < formats[r].count {
                        workbook.sheets[index].setFormat(formats[r][c] ?? CellFormat(), at: address)
                    }
                }
            }
        }
        let width = max(grid.map(\.count).max() ?? 1, 1)
        selection = GridSelection(anchor: origin.offset(rows: grid.count - 1, columns: width - 1).clamped(), active: origin)
    }

    // MARK: - Editing commands

    /// Copies the top row of the selection downward, moving relative references.
    func fillDown() {
        commitEdit(moveRows: 0, moveColumns: 0)
        let range = selection.range
        guard range.rowCount > 1 else { return }
        let index = activeSheet
        mutate("Fill Down") { workbook in
            for column in range.start.column...range.end.column {
                let source = CellAddress(row: range.start.row, column: column)
                let raw = workbook.sheets[index].cells[source] ?? ""
                let format = workbook.sheets[index].formats[source] ?? CellFormat()
                for row in (range.start.row + 1)...range.end.row {
                    let target = CellAddress(row: row, column: column)
                    workbook.sheets[index].setInput(
                        CellInput.isFormula(raw) ? FormulaText.shifted(raw, rows: row - range.start.row, columns: 0) : raw,
                        at: target
                    )
                    workbook.sheets[index].setFormat(format, at: target)
                }
            }
        }
    }

    /// Applies a function to the run of numbers above the active cell, or to its left.
    func autoSum(_ function: String = "SUM") {
        commitEdit(moveRows: 0, moveColumns: 0)
        let target = selection.active
        let calc = calculator
        let index = activeSheet
        func isNumber(_ address: CellAddress) -> Bool { calc.value(sheet: index, at: address).isNumber }

        var row = target.row - 1
        while row >= 0, isNumber(CellAddress(row: row, column: target.column)) { row -= 1 }
        var column = target.column - 1
        while column >= 0, isNumber(CellAddress(row: target.row, column: column)) { column -= 1 }

        let range: CellRange
        if row < target.row - 1 {
            range = CellRange(CellAddress(row: row + 1, column: target.column), target.offset(rows: -1, columns: 0))
        } else if column < target.column - 1 {
            range = CellRange(CellAddress(row: target.row, column: column + 1), target.offset(rows: 0, columns: -1))
        } else {
            beginEditing(at: target, text: "=\(function)(")
            return
        }
        mutate("AutoSum") { $0.sheets[index].setInput("=\(function)(\(range.a1))", at: target) }
    }

    // MARK: - Formatting

    func updateFormats(_ actionName: String, _ change: (inout CellFormat) -> Void) {
        updateFormatsByAddress(actionName) { _, format in change(&format) }
    }

    private func updateFormatsByAddress(_ actionName: String, _ change: (CellAddress, inout CellFormat) -> Void) {
        let index = activeSheet
        let addresses = selection.range.addresses
        mutate(actionName) { workbook in
            for address in addresses {
                var format = workbook.sheets[index].formats[address] ?? CellFormat()
                change(address, &format)
                workbook.sheets[index].setFormat(format, at: address)
            }
        }
    }

    /// Turns a style on for the whole selection, or off if every cell already has it.
    func toggle(_ keyPath: WritableKeyPath<CellFormat, Bool>, _ actionName: String) {
        let allOn = selection.range.addresses.allSatisfy { (sheet.formats[$0] ?? CellFormat())[keyPath: keyPath] }
        updateFormats(actionName) { $0[keyPath: keyPath] = !allOn }
    }

    static let fontSizes: [Double] = [8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 36, 48, 72]
    static let commonFonts = ["Aptos", "Calibri", "Arial", "Helvetica Neue", "Avenir Next", "Georgia",
                              "Times New Roman", "Palatino", "Verdana", "Trebuchet MS", "Gill Sans", "Futura",
                              "Courier New", "Menlo", "Comic Sans MS"]

    static var installedFonts: [String] {
        #if os(macOS)
        NSFontManager.shared.availableFontFamilies.sorted()
        #else
        UIFont.familyNames.sorted()
        #endif
    }

    func setFontName(_ name: String) {
        let defaultName = workbook.defaultFontName
        updateFormats("Font") { $0.fontName = name == defaultName ? nil : name }
    }

    func setFontSize(_ size: Double) {
        let defaultSize = workbook.defaultFontSize
        updateFormats("Font Size") { $0.fontSize = size == defaultSize ? nil : size }
    }

    func stepFontSize(up: Bool) {
        let current = activeFontSize
        let next = up
            ? Self.fontSizes.first { $0 > current } ?? current
            : Self.fontSizes.last { $0 < current } ?? current
        setFontSize(next)
    }

    func setNumberFormat(_ code: String) {
        updateFormats("Number Format") { $0.numberFormat = code }
    }

    func stepDecimals(_ delta: Int) {
        updateFormats(delta > 0 ? "Increase Decimal" : "Decrease Decimal") {
            $0.numberFormat = ExcelNumberFormat.adjustingDecimals($0.numberFormat, by: delta)
        }
    }

    func stepIndent(_ delta: Int) {
        updateFormats(delta > 0 ? "Increase Indent" : "Decrease Indent") {
            $0.indent = min(15, max(0, $0.indent + delta))
            if $0.indent > 0, $0.alignment == .general || $0.alignment == .center { $0.alignment = .left }
        }
    }

    func showCustomFormat() {
        model.formatDraft = FormatDraft(code: activeFormat.numberFormat,
                                        sample: calculator.value(sheet: activeSheet, at: selection.active))
    }

    func applyCellStyle(_ style: CellStylePreset) {
        updateFormats("Cell Style") { $0 = style.apply(to: $0) }
    }

    /// Sets lines on the outer edges of the selection; `all` also draws the inside lines.
    func applyBorders(_ sides: CellBorder, all: Bool = false, _ actionName: String) {
        let range = selection.range
        updateFormatsByAddress(actionName) { address, format in
            if all {
                format.border = sides
                return
            }
            if let line = sides.top, address.row == range.start.row { format.border.top = line }
            if let line = sides.bottom, address.row == range.end.row { format.border.bottom = line }
            if let line = sides.left, address.column == range.start.column { format.border.left = line }
            if let line = sides.right, address.column == range.end.column { format.border.right = line }
        }
    }

    func clearBorders() {
        updateFormats("No Border") { $0.border = CellBorder() }
    }

    // MARK: - Merging

    private func intersects(_ a: CellRange, _ b: CellRange) -> Bool {
        a.start.row <= b.end.row && b.start.row <= a.end.row && a.start.column <= b.end.column && b.start.column <= a.end.column
    }

    /// Merge & Center, Merge Across (one merge per row) or Merge Cells. Only the top-left values are kept, as in Excel.
    func mergeSelection(center: Bool, across: Bool) {
        commitEdit(moveRows: 0, moveColumns: 0)
        let range = selection.range
        guard range.cellCount > 1 else { return }
        let areas = across
            ? (range.start.row...range.end.row).map { CellRange(CellAddress(row: $0, column: range.start.column), CellAddress(row: $0, column: range.end.column)) }
            : [range]
        let lost = areas.flatMap { area in storedAddresses(in: area).filter { $0 != area.start } }
        let index = activeSheet
        mutate(center ? "Merge & Center" : "Merge Cells") { workbook in
            workbook.sheets[index].merges.removeAll { existing in areas.contains { intersects($0, existing) } }
            for area in areas where area.cellCount > 1 {
                workbook.sheets[index].merges.append(area)
                for address in workbook.sheets[index].cells.keys where area.contains(address) && address != area.start {
                    workbook.sheets[index].cells.removeValue(forKey: address)
                }
                if center {
                    var format = workbook.sheets[index].formats[area.start] ?? CellFormat()
                    format.alignment = .center
                    workbook.sheets[index].setFormat(format, at: area.start)
                }
            }
        }
        if !lost.isEmpty {
            model.message = "Merging keeps only the upper-left value, so \(lost.count) other value\(lost.count == 1 ? " was" : "s were") removed. Use Undo (⌘Z) to get \(lost.count == 1 ? "it" : "them") back."
        }
    }

    func unmergeSelection() {
        let range = selection.range
        let index = activeSheet
        mutate("Unmerge Cells") { workbook in
            workbook.sheets[index].merges.removeAll { intersects($0, range) }
        }
    }

    // MARK: - Conditional formatting

    /// The cells a new rule covers: the selection, or the data around a single selected cell.
    private var ruleRange: CellRange {
        selection.range.cellCount > 1 ? selection.range : sheet.currentRegion(around: selection.active)
    }

    private func addRule(_ rule: ConditionalRule, range: CellRange, _ actionName: String) {
        let index = activeSheet
        // New rules take priority over older ones, as in Excel.
        mutate(actionName) { $0.sheets[index].conditionalFormats.insert(ConditionalFormat(ranges: [range], rule: rule), at: 0) }
    }

    func startRule(_ kind: RuleDraft.Kind) {
        let suggestion: String = switch kind {
        case .top, .bottom: "10"
        case .topPercent, .bottomPercent: "10"
        default: ""
        }
        model.ruleDraft = RuleDraft(kind: kind, range: ruleRange, first: suggestion)
    }

    /// Turns dialog input into formula text: `=B2` stays a formula, numbers stay numbers, anything else is quoted text.
    private func ruleOperand(_ input: String) -> String {
        let text = input.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("=") { return String(text.dropFirst()) }
        if CellInput.parseNumber(text) != nil { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    func applyRule(_ draft: RuleDraft) {
        let style = draft.style.style
        let rule: ConditionalRule
        switch draft.kind {
        case .greaterThan: rule = .cellIs(.greaterThan, ruleOperand(draft.first), nil, style)
        case .lessThan: rule = .cellIs(.lessThan, ruleOperand(draft.first), nil, style)
        case .equalTo: rule = .cellIs(.equal, ruleOperand(draft.first), nil, style)
        case .between: rule = .cellIs(.between, ruleOperand(draft.first), ruleOperand(draft.second), style)
        case .textContains: rule = .text(.containsText, draft.first, style)
        case .top, .bottom, .topPercent, .bottomPercent:
            let rank = max(1, Int(draft.first.trimmingCharacters(in: .whitespaces)) ?? 10)
            rule = .top(rank: rank, bottom: draft.kind == .bottom || draft.kind == .bottomPercent,
                        percent: draft.kind == .topPercent || draft.kind == .bottomPercent, style)
        case .formula:
            let text = draft.first.trimmingCharacters(in: .whitespaces)
            rule = .expression(text.hasPrefix("=") ? String(text.dropFirst()) : text, style)
        }
        addRule(rule, range: draft.range, draft.kind.rawValue)
    }

    func addDuplicateRule(unique: Bool) {
        addRule(.duplicates(unique: unique, .lightRedFillDarkRedText), range: ruleRange, unique ? "Unique Values" : "Duplicate Values")
    }

    func addAverageRule(below: Bool) {
        addRule(.average(below: below, below ? .yellowFillDarkYellowText : .greenFillDarkGreenText), range: ruleRange,
                below ? "Below Average" : "Above Average")
    }

    func addDataBar(_ hex: String) {
        addRule(.dataBar(SheetCore.RGBColor(hex: hex)!), range: ruleRange, "Data Bars")
    }

    func addColorScale(_ hexes: [String]) {
        let colors = hexes.compactMap { SheetCore.RGBColor(hex: $0) }
        let stops: [ScaleStop] = colors.count == 3
            ? [ScaleStop(.min, color: colors[0]), ScaleStop(.percentile, "50", color: colors[1]), ScaleStop(.max, color: colors[2])]
            : [ScaleStop(.min, color: colors[0]), ScaleStop(.max, color: colors[1])]
        addRule(.colorScale(stops), range: ruleRange, "Color Scale")
    }

    func clearRules(sheetWide: Bool) {
        let index = activeSheet
        let range = selection.range
        mutate("Clear Rules") { workbook in
            if sheetWide {
                workbook.sheets[index].conditionalFormats = []
            } else {
                workbook.sheets[index].conditionalFormats.removeAll { rule in rule.ranges.contains { intersects($0, range) } }
            }
        }
    }

    // MARK: - Rows and columns

    private func applyStructure(_ change: StructuralChange, _ actionName: String) {
        commitEdit(moveRows: 0, moveColumns: 0)
        let index = activeSheet
        mutate(actionName) { $0.apply(change, toSheet: index) }
    }

    func insertRows(below: Bool) {
        let range = selection.range
        applyStructure(.insertRows(at: below ? range.end.row + 1 : range.start.row, count: range.rowCount), "Insert Rows")
        if below { selection = GridSelection(CellAddress(row: range.end.row + 1, column: range.start.column)) }
    }

    func insertColumns(right: Bool) {
        let range = selection.range
        applyStructure(.insertColumns(at: right ? range.end.column + 1 : range.start.column, count: range.columnCount), "Insert Columns")
        if right { selection = GridSelection(CellAddress(row: range.start.row, column: range.end.column + 1)) }
    }

    func deleteRows() {
        let range = selection.range
        applyStructure(.deleteRows(at: range.start.row, count: range.rowCount), "Delete Rows")
        selection = GridSelection(range.start)
    }

    func deleteColumns() {
        let range = selection.range
        applyStructure(.deleteColumns(at: range.start.column, count: range.columnCount), "Delete Columns")
        selection = GridSelection(range.start)
    }

    func hideRows() {
        let range = selection.range
        let index = activeSheet
        mutate("Hide Rows") { $0.sheets[index].hiddenRows.formUnion(range.start.row...range.end.row) }
        move(rows: 1, columns: 0, extend: false)
    }

    /// Unhides the hidden rows inside or next to the selection.
    func unhideRows() {
        let range = selection.range
        let hidden = sheet.hiddenRows
        var low = range.start.row - 1
        while low >= 0, hidden.contains(low) { low -= 1 }
        var high = range.end.row + 1
        while hidden.contains(high) { high += 1 }
        let index = activeSheet
        mutate("Unhide Rows") { workbook in
            workbook.sheets[index].hiddenRows = workbook.sheets[index].hiddenRows.filter { $0 <= low || $0 >= high }
        }
    }

    func unhideAllRows() {
        let index = activeSheet
        mutate("Unhide All Rows") { $0.sheets[index].hiddenRows = [] }
    }

    func hideColumns() {
        let range = selection.range
        let index = activeSheet
        mutate("Hide Columns") { $0.sheets[index].hiddenColumns.formUnion(range.start.column...range.end.column) }
        move(rows: 0, columns: 1, extend: false)
    }

    func unhideColumns() {
        let range = selection.range
        let hidden = sheet.hiddenColumns
        var low = range.start.column - 1
        while low >= 0, hidden.contains(low) { low -= 1 }
        var high = range.end.column + 1
        while hidden.contains(high) { high += 1 }
        let index = activeSheet
        mutate("Unhide Columns") { workbook in
            workbook.sheets[index].hiddenColumns = workbook.sheets[index].hiddenColumns.filter { $0 <= low || $0 >= high }
        }
    }

    func unhideAllColumns() {
        let index = activeSheet
        mutate("Unhide All Columns") { $0.sheets[index].hiddenColumns = [] }
    }

    /// Widens selected columns to fit their longest shown text.
    func autofitColumns() {
        let range = selection.range
        let calc = calculator
        let index = activeSheet
        var widths: [Int: Double] = [:]
        for address in sheet.cells.keys where (range.start.column...range.end.column).contains(address.column) {
            guard sheet.merge(containing: address) == nil else { continue }
            let text = calc.displayText(sheet: index, at: address)
            let size = sheet.formats[address]?.fontSize ?? workbook.defaultFontSize
            let width = Double(text.count) * size * 0.62 + 12
            widths[address.column] = max(widths[address.column] ?? 24, min(width, 600))
        }
        guard !widths.isEmpty else { return }
        mutate("AutoFit Column Width") { workbook in
            for (column, width) in widths { workbook.sheets[index].columnWidths[column] = width }
        }
    }

    func resetColumnWidths() {
        let range = selection.range
        let index = activeSheet
        mutate("Reset Column Width") { workbook in
            for column in range.start.column...range.end.column { workbook.sheets[index].columnWidths.removeValue(forKey: column) }
        }
    }

    /// Removes fixed heights so rows size to their fonts again.
    func autofitRows() {
        let range = selection.range
        let index = activeSheet
        mutate("AutoFit Row Height") { workbook in
            for row in range.start.row...range.end.row { workbook.sheets[index].rowHeights.removeValue(forKey: row) }
        }
    }

    // MARK: - Sorting and filtering

    /// The data a sort or filter command applies to: the filter's range, the selection, or the current region.
    private func dataTarget() -> (range: CellRange, hasHeader: Bool) {
        if let filter = sheet.filter, filter.range.contains(selection.active) {
            return (refreshedFilterRange(filter), true)
        }
        let range = selection.range.cellCount > 1 ? selection.range : sheet.currentRegion(around: selection.active)
        return (range, looksLikeHeader(range))
    }

    /// A first row of text above a row containing numbers, or a bold first row, is a header.
    private func looksLikeHeader(_ range: CellRange) -> Bool {
        guard range.rowCount > 1 else { return false }
        let calc = calculator
        let columns = range.start.column...range.end.column
        let first = columns.map { calc.value(sheet: activeSheet, at: CellAddress(row: range.start.row, column: $0)) }
        let second = columns.map { calc.value(sheet: activeSheet, at: CellAddress(row: range.start.row + 1, column: $0)) }
        let firstIsText = first.contains { $0 != .empty } && first.allSatisfy { value in
            if case .text = value { return true }
            return value == .empty
        }
        let secondHasData = second.contains { $0.isNumber || $0 == .boolean(true) || $0 == .boolean(false) }
        let firstIsBold = columns.allSatisfy { sheet.formats[CellAddress(row: range.start.row, column: $0)]?.bold == true }
        return firstIsText && (secondHasData || firstIsBold)
    }

    private func refreshedFilterRange(_ filter: AutoFilter) -> CellRange {
        let region = sheet.currentRegion(around: filter.range.start)
        return CellRange(filter.range.start, CellAddress(row: max(region.end.row, filter.range.end.row), column: filter.range.end.column))
    }

    func sortSelection(ascending: Bool) {
        sortByColumn(selection.active.column, ascending: ascending)
    }

    func sortByColumn(_ column: Int, ascending: Bool) {
        commitEdit(moveRows: 0, moveColumns: 0)
        var (range, hasHeader) = dataTarget()
        if !range.contains(CellAddress(row: range.start.row, column: column)) {
            range = sheet.currentRegion(around: CellAddress(row: max(selection.active.row, 0), column: column))
            hasHeader = looksLikeHeader(range)
        }
        guard range.rowCount > (hasHeader ? 2 : 1) else { return }
        if sheet.merges.contains(where: { intersects($0, range) }) {
            model.message = "Sorting needs cells of the same size. Unmerge the cells in \(range.a1) first."
            return
        }
        let index = activeSheet
        mutate(ascending ? "Sort A to Z" : "Sort Z to A") {
            $0.sort(sheet: index, range: range, byColumn: column, ascending: ascending, hasHeader: hasHeader)
        }
    }

    func sortFilter(byColumn column: Int, ascending: Bool) {
        guard let filter = sheet.filter else { return }
        let range = refreshedFilterRange(filter)
        let index = activeSheet
        mutate(ascending ? "Sort A to Z" : "Sort Z to A") {
            $0.sheets[index].filter?.range = range
            $0.sort(sheet: index, range: range, byColumn: column, ascending: ascending, hasHeader: true)
        }
    }

    func toggleFilter() {
        commitEdit(moveRows: 0, moveColumns: 0)
        let index = activeSheet
        if sheet.filter != nil {
            mutate("Remove Filter") { $0.sheets[index].filter = nil }
            return
        }
        let range = selection.range.cellCount > 1 ? selection.range : sheet.currentRegion(around: selection.active)
        guard !storedAddresses(in: range).isEmpty else {
            model.message = "Select a cell in your data, with headings in the first row, before turning on the filter."
            return
        }
        mutate("Filter") { $0.sheets[index].filter = AutoFilter(range: range) }
    }

    func clearFilterCriteria() {
        let index = activeSheet
        mutate("Clear Filter") { $0.sheets[index].filter?.allowedValues = [:] }
    }

    /// Distinct shown values of a filter column, in sort order with blanks last.
    func filterValues(_ column: Int) -> [String] {
        guard let filter = sheet.filter else { return [] }
        let range = refreshedFilterRange(filter)
        guard range.rowCount > 1 else { return [] }
        let calc = calculator
        var seen = Set<String>()
        var values: [(text: String, value: CellValue)] = []
        for row in (range.start.row + 1)...range.end.row {
            let address = CellAddress(row: row, column: column)
            let text = calc.displayText(sheet: activeSheet, at: address)
            if seen.insert(text).inserted { values.append((text, calc.value(sheet: activeSheet, at: address))) }
        }
        return values.sorted { a, b in
            if a.text.isEmpty != b.text.isEmpty { return !a.text.isEmpty }
            return Calculator.compareForSort(a.value, b.value)
        }.map(\.text)
    }

    func applyFilter(column: Int, allowed: Set<String>?) {
        guard let filter = sheet.filter else { return }
        let range = refreshedFilterRange(filter)
        let index = activeSheet
        mutate("Filter") { workbook in
            workbook.sheets[index].filter?.range = range
            if let allowed {
                workbook.sheets[index].filter?.allowedValues[column] = allowed
            } else {
                workbook.sheets[index].filter?.allowedValues.removeValue(forKey: column)
            }
        }
    }

    func filterBySelectedValue() {
        let column = selection.active.column
        let text = calculator.displayText(sheet: activeSheet, at: selection.active)
        if sheet.filter == nil {
            let region = sheet.currentRegion(around: selection.active)
            let index = activeSheet
            mutate("Filter") { $0.sheets[index].filter = AutoFilter(range: region) }
        }
        applyFilter(column: column, allowed: [text])
    }

    func removeDuplicates() {
        commitEdit(moveRows: 0, moveColumns: 0)
        let (range, hasHeader) = dataTarget()
        let index = activeSheet
        var removed = 0
        mutate("Remove Duplicates") { removed = $0.removeDuplicates(sheet: index, range: range, hasHeader: hasHeader) }
        model.message = removed == 0
            ? "No duplicate rows were found in \(range.a1)."
            : "Removed \(removed) duplicate row\(removed == 1 ? "" : "s") from \(range.a1)."
    }

    // MARK: - View

    func setFrozenRows(_ rows: Int) {
        let index = activeSheet
        mutate(rows == 0 ? "Unfreeze Panes" : "Freeze Panes") { $0.sheets[index].frozenRows = max(0, min(rows, 50)) }
    }

    func toggleGridlines() {
        let index = activeSheet
        mutate("Gridlines") { $0.sheets[index].showGridlines.toggle() }
    }

    func setZoom(_ zoom: Double) {
        model.zoom = min(2.5, max(0.5, (zoom * 20).rounded() / 20))
    }

    // MARK: - Find and replace

    func showFind() {
        model.findVisible = true
        model.findStatus = ""
        DispatchQueue.main.async { focus = .find }
    }

    func findNext() {
        guard let found = calculator.find(model.findText, sheet: activeSheet, after: selection.active, matchCase: model.matchCase) else {
            model.findStatus = model.findText.isEmpty ? "" : "No matches"
            return
        }
        model.findStatus = ""
        select(found)
    }

    func replaceCurrent() {
        let index = activeSheet
        let query = model.findText
        let replacement = model.replaceText
        let matchCase = model.matchCase
        let active = selection.active
        mutate("Replace") { _ = $0.replace(query, with: replacement, sheet: index, cells: [active], matchCase: matchCase) }
        findNext()
    }

    func replaceAll() {
        let index = activeSheet
        let query = model.findText
        let replacement = model.replaceText
        let matchCase = model.matchCase
        let cells = Array(sheet.cells.keys)
        var count = 0
        mutate("Replace All") { count = $0.replace(query, with: replacement, sheet: index, cells: cells, matchCase: matchCase) }
        model.findStatus = "Replaced in \(count) cell\(count == 1 ? "" : "s")"
    }

    // MARK: - Charts

    /// Charts the selection (or the data around the active cell): a text first row names the
    /// series, a text first column labels the categories.
    func insertChart(_ kind: ChartKind) {
        commitEdit(moveRows: 0, moveColumns: 0)
        let range = selection.range.cellCount > 1 ? selection.range : sheet.currentRegion(around: selection.active)
        let calc = calculator
        let index = activeSheet
        func value(_ row: Int, _ column: Int) -> CellValue { calc.value(sheet: index, at: CellAddress(row: row, column: column)) }
        func isText(_ v: CellValue) -> Bool {
            if case .text = v { return true }
            return false
        }

        let headerRow = range.rowCount > 1 && (range.start.column...range.end.column).contains { isText(value(range.start.row, $0)) }
        let dataRows = Array((headerRow ? range.start.row + 1 : range.start.row)...range.end.row)
        let labelColumn = range.columnCount > 1 && dataRows.contains { !value($0, range.start.column).isNumber }
        let seriesColumns = Array((labelColumn ? range.start.column + 1 : range.start.column)...range.end.column)
        let series = seriesColumns.map { column in
            ChartSeries(
                name: headerRow ? calc.displayText(sheet: index, at: CellAddress(row: range.start.row, column: column)) : "Column " + CellAddress.columnName(column),
                values: dataRows.map { row in
                    if case .number(let n) = value(row, column) { return n }
                    return 0
                }
            )
        }
        guard series.contains(where: { $0.values.contains { $0 != 0 } }) else {
            model.message = "Select numbers to chart, with labels in the first column and a header row if you have them."
            return
        }
        let categories = dataRows.map { row in
            labelColumn ? calc.displayText(sheet: index, at: CellAddress(row: row, column: range.start.column)) : String(row + 1)
        }
        model.chart = ChartRequest(kind: kind, title: "\(sheet.name)!\(range.a1)", categories: categories, series: series)
    }

    // MARK: - Sheets

    func switchSheet(_ index: Int) {
        commitEdit(moveRows: 0, moveColumns: 0)
        sheetIndex = index
        selection = GridSelection(CellAddress(row: 0, column: 0))
        focus = .grid
    }

    func addSheet() {
        var added = 0
        mutate("New Sheet") { added = $0.addSheet() }
        switchSheet(added)
    }

    func deleteSheet(_ index: Int) {
        mutate("Delete Sheet") { $0.removeSheet(at: index) }
        switchSheet(max(0, min(index, workbook.sheets.count - 1)))
    }

    func startRename(_ index: Int) {
        model.renameText = workbook.sheets[index].name
        model.renaming = index
    }
}
