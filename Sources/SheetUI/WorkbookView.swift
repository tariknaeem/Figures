import SheetCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The spreadsheet window: ribbon, formula bar, cell grid, sheet tabs and status bar.
/// Commands live in WorkbookView+Actions.swift and the ribbon in WorkbookView+Ribbon.swift.
public struct WorkbookView: View {
    @Binding var workbook: Workbook
    @Environment(\.undoManager) var undoManager
    @StateObject var model = GridModel()
    @FocusState var focus: FocusField?

    /// Screen points per Excel point at 100% zoom.
    static let pointScale: CGFloat = 1.2
    static let rowHeaderWidth: CGFloat = 46
    static let headerHeight: CGFloat = 20
    static let headerBackground = Color(red: 0.95, green: 0.95, blue: 0.95)
    static let gridColor = Color(red: 0.84, green: 0.84, blue: 0.84)

    public init(workbook: Binding<Workbook>) {
        _workbook = workbook
    }

    var sheetIndex: Int {
        get { model.sheetIndex }
        nonmutating set { model.sheetIndex = newValue }
    }
    var selection: GridSelection {
        get { model.selection }
        nonmutating set { model.selection = newValue }
    }
    var editor: CellEditor? {
        get { model.editor }
        nonmutating set { model.editor = newValue }
    }

    var activeSheet: Int { min(sheetIndex, workbook.sheets.count - 1) }
    var sheet: Sheet { workbook.sheets[activeSheet] }
    var calculator: Calculator { model.cache.calculator(for: workbook) }
    var activeFormat: CellFormat { sheet.formats[selection.active] ?? CellFormat() }
    var zoom: CGFloat { CGFloat(model.zoom) }
    var activeFontName: String { activeFormat.fontName ?? workbook.defaultFontName }
    var activeFontSize: Double { activeFormat.fontSize ?? workbook.defaultFontSize }

    public var body: some View {
        VStack(spacing: 0) {
            ribbon
            Divider()
            if model.findVisible {
                findBar
                Divider()
            }
            formulaBar
                .sheet(item: $model.formatDraft) { draft in
                    FormatSheet(draft: draft) { code in updateFormats("Number Format") { $0.numberFormat = code } }
                }
            Divider()
            ZStack(alignment: .topLeading) {
                grid
                formulaAssist
            }
            .sheet(item: $model.ruleDraft) { draft in
                RuleSheet(draft: draft) { applyRule($0) }
            }
            .background {
                Color.clear.sheet(item: $model.controlDraft) { draft in
                    ControlSheet(draft: draft) { applyControl($0) }
                }
            }
            Divider()
            bottomBar
        }
        .background { shortcutButtons }
        .alert("Rename Sheet", isPresented: Binding(get: { model.renaming != nil }, set: { if !$0 { model.renaming = nil } })) {
            TextField("Name", text: $model.renameText)
            Button("Rename") {
                if let index = model.renaming {
                    let name = model.renameText
                    mutate("Rename Sheet") { _ = $0.renameSheet(at: index, to: name) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Up to 31 characters, without [ ] : * ? / \\")
        }
        .alert(model.message ?? "", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .sheet(item: $model.chart) { ChartPanel(request: $0) }
        .onAppear { focus = .grid }
    }

    // MARK: - Formula bar

    private var formulaBar: some View {
        HStack(spacing: 8) {
            TextField("", text: nameBoxText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .frame(width: 90)
                .padding(.leading, 8)
                .focused($focus, equals: .nameBox)
                .onSubmit { goToNameBox() }
                .help("Name Box: type a cell such as B12 or a range such as A1:C10")
            Divider().frame(height: 18)
            Text("fx")
                .font(.system(size: 13, design: .serif))
                .italic()
                .foregroundStyle(.secondary)
            TextField("", text: formulaBarText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focus, equals: .formulaBar)
                .onSubmit { commitEdit(moveRows: 1, moveColumns: 0) }
                #if os(macOS)
                .onExitCommand { cancelEdit() }
                #endif
        }
        .frame(height: 30)
    }

    private var nameBoxText: Binding<String> {
        Binding(get: { model.nameBox ?? selection.range.a1 }, set: { model.nameBox = $0 })
    }

    private var formulaBarText: Binding<String> {
        Binding(
            get: { editor?.text ?? sheet.cells[selection.active] ?? "" },
            set: { newValue in
                if editor == nil {
                    editor = CellEditor(address: selection.active, text: newValue, inCell: false)
                } else {
                    editor?.text = newValue
                }
            }
        )
    }

    private var cellEditorText: Binding<String> {
        Binding(get: { editor?.text ?? "" }, set: { editor?.text = $0 })
    }

    /// Function suggestions or the current function's arguments, floating over the grid.
    @ViewBuilder
    private var formulaAssist: some View {
        if let editor, editor.text.hasPrefix("=") {
            let assist = FormulaAssist(text: editor.text)
            if !assist.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(assist.suggestions.prefix(8)) { info in
                        Button { acceptSuggestion(info.name, replacing: assist.prefix) } label: {
                            HStack(spacing: 8) {
                                Text(info.name).font(.system(size: 12, weight: .semibold, design: .monospaced))
                                Text(info.summary).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 380)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                .shadow(radius: 4)
                .padding(.leading, 150)
                .padding(.top, 2)
            } else if let info = assist.currentFunction {
                Text(info.signature)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(6)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .shadow(radius: 2)
                    .padding(.leading, 150)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Grid

    var rowCount: Int {
        min(CellAddress.maxRows, max(200, model.bounds(of: workbook, sheet: activeSheet).row + 50, selection.active.row + 30))
    }

    var columnCount: Int {
        min(CellAddress.maxColumns, max(26, model.bounds(of: workbook, sheet: activeSheet).column + 5, selection.active.column + 5))
    }

    /// The sheet's layout and cell appearance, rebuilt only when the workbook, zoom or shown columns change.
    var layout: GridLayout {
        let key = GridLayout.Key(version: workbook.version, sheet: activeSheet, zoom: model.zoom,
                                 showFormulas: model.showFormulas, columnCount: columnCount)
        if let layout = model.layout, layout.key == key { return layout }
        let layout = GridLayout(key: key, workbook: workbook, calculator: calculator)
        model.layout = layout
        return layout
    }

    func columnWidth(_ column: Int) -> CGFloat {
        layout.width(column)
    }

    private var grid: some View {
        let layout = layout
        let rows = rowCount
        let frozen = min(sheet.frozenRows, rows)
        let bodyRows = (frozen..<rows).filter { !layout.hidden.contains($0) }
        let frozenRows = (0..<frozen).filter { !layout.hidden.contains($0) }
        let context = RowContext(selection: selection, editor: editor, filter: sheet.filter, openFilterColumn: model.filterColumn,
                                 fillPreview: model.fillPreview)
        configureActions()

        return ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(bodyRows, id: \.self) { row in
                            rowView(row, layout, context)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 0) {
                            columnHeader(layout.columns)
                            ForEach(frozenRows, id: \.self) { row in
                                rowView(row, layout, context)
                            }
                            if frozen > 0 {
                                Rectangle().fill(Color.gray.opacity(0.7)).frame(height: 1.5)
                            }
                        }
                        .background(Color.white)
                    }
                }
            }
            .background(Color.white)
            .onChange(of: selection.active) { _, active in
                if active.row >= frozen { proxy.scrollTo(active) }
            }
        }
        // Workbooks are designed on white paper, so the sheet stays light in Dark Mode.
        .environment(\.colorScheme, .light)
        .focusable()
        .focused($focus, equals: .grid)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat]) { handleKey($0) }
        #if os(macOS)
        .onCopyCommand { copySelection() }
        .onCutCommand { cutSelection() }
        .onPasteCommand(of: [.plainText, .utf8PlainText]) { _ in pasteFromSystem() }
        .onDeleteCommand { clearSelection() }
        #endif
    }

    /// What every row needs to know about the window, read once per update.
    private struct RowContext {
        let selection: GridSelection
        let editor: CellEditor?
        let filter: AutoFilter?
        let openFilterColumn: Int?
        let fillPreview: CellRange?
    }

    private func rowView(_ row: Int, _ layout: GridLayout, _ context: RowContext) -> some View {
        let range = context.selection.range
        let inRows = (range.start.row...range.end.row).contains(row)
        var selection = RowSelection(headerSelected: inRows)
        if context.selection.active.row == row { selection.activeColumn = context.selection.active.column }
        if range.cellCount > 1, inRows { selection.rangeColumns = range.start.column...range.end.column }
        if context.editor == nil, row == range.end.row { selection.handleColumn = range.end.column }
        if let preview = context.fillPreview, (preview.start.row...preview.end.row).contains(row) {
            selection.fillColumns = preview.start.column...preview.end.column
        }
        let filtered = context.filter.map { !$0.allowedValues.isEmpty && $0.dataRows?.contains(row) == true } ?? false
        let editor = context.editor.flatMap { $0.inCell && $0.address.row == row ? $0 : nil }
        let openFilter = context.filter?.range.start.row == row ? context.openFilterColumn : nil
        return RowView(render: layout.row(row), selection: selection, filtered: filtered, editor: editor,
                       openFilterColumn: openFilter, zoom: zoom, actions: model.actions, focus: $focus)
            .equatable()
    }

    /// Points the row views' callbacks at this window.
    private func configureActions() {
        let actions = model.actions
        actions.perform = { perform($0) }
        actions.editorText = cellEditorText
        actions.filterPopover = { column in AnyView(filterPopover(column)) }
    }

    private func perform(_ command: GridCommand) {
        switch command {
        case .tap(let address): cellTapped(address)
        case .cut: _ = cutSelection()
        case .copy: _ = copySelection()
        case .paste: pasteFromSystem()
        case .pasteSpecial(let kind): pasteSpecial(kind)
        case .insertRows(let below): insertRows(below: below)
        case .insertColumns(let right): insertColumns(right: right)
        case .deleteRows: deleteRows()
        case .deleteColumns: deleteColumns()
        case .clearContents: clearSelection()
        case .sort(let ascending): sortSelection(ascending: ascending)
        case .filterBySelection: filterBySelectedValue()
        case .merge: mergeSelection(center: true, across: false)
        case .unmerge: unmergeSelection()
        case .formatCells: showCustomFormat()
        case .openFilter(let column): model.filterColumn = column
        case .closeFilter: model.filterColumn = nil
        case .selectRow(let row): selectRow(row)
        case .rowMenu(let item, let row):
            selectRow(row)
            switch item {
            case .insertAbove: insertRows(below: false)
            case .insertBelow: insertRows(below: true)
            case .delete: deleteRows()
            case .hide: hideRows()
            case .unhide: unhideRows()
            case .autofit: autofitRows()
            }
        case .resizeRow(let row, let startHeight, let translation):
            if model.resizingRow?.row != row { model.resizingRow = (row, startHeight) }
            let screen = max(6, (model.resizingRow?.startHeight ?? startHeight) + translation)
            workbook.sheets[activeSheet].rowHeights[row] = Double(screen / (Self.pointScale * zoom))
        case .endRowResize: model.resizingRow = nil
        case .commitEdit(let rows, let columns): commitEdit(moveRows: rows, moveColumns: columns)
        case .cancelEdit: cancelEdit()
        case .setControl(let address, let value):
            setControlValue(at: address, to: value)
        case .fillDrag(let translation):
            model.fillPreview = fillTarget(for: translation)
        case .fillEnd:
            if let target = model.fillPreview { autofillSelection(to: target) }
            model.fillPreview = nil
        case .editorTab:
            guard let editor else { return }
            let assist = FormulaAssist(text: editor.text)
            if let first = assist.suggestions.first {
                acceptSuggestion(first.name, replacing: assist.prefix)
            } else {
                commitEdit(moveRows: 0, moveColumns: 1)
            }
        }
    }

    private func filterPopover(_ column: Int) -> some View {
        FilterPopover(
            values: filterValues(column),
            allowed: sheet.filter?.allowedValues[column],
            onSort: { ascending in
                model.filterColumn = nil
                sortFilter(byColumn: column, ascending: ascending)
            },
            onApply: { allowed in
                model.filterColumn = nil
                applyFilter(column: column, allowed: allowed)
            },
            onCancel: { model.filterColumn = nil }
        )
        .environment(\.colorScheme, .light)
    }

    private var headerLine: some View {
        Rectangle().stroke(Self.gridColor, lineWidth: 0.5)
    }

    private func columnHeader(_ columns: [Int]) -> some View {
        let selected = selection.range.start.column...selection.range.end.column
        return HStack(spacing: 0) {
            Self.headerBackground
                .frame(width: Self.rowHeaderWidth, height: Self.headerHeight * zoom)
                .overlay(headerLine)
                .contentShape(Rectangle())
                .onTapGesture { selectAll() }
                .help("Select All")
            ForEach(columns, id: \.self) { column in
                Text(CellAddress.columnName(column))
                    .font(.system(size: 11 * zoom, weight: selected.contains(column) ? .semibold : .regular))
                    .foregroundStyle(Color(white: 0.35))
                    .frame(width: columnWidth(column), height: Self.headerHeight * zoom)
                    .background(selected.contains(column) ? Color.accentColor.opacity(0.18) : Self.headerBackground)
                    .overlay(headerLine)
                    .contentShape(Rectangle())
                    .onTapGesture { selectColumn(column) }
                    .contextMenu { columnMenu(column) }
                    .overlay(alignment: .trailing) { resizeHandle(column) }
            }
        }
    }

    private func resizeHandle(_ column: Int) -> some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        if model.resizing?.column != column {
                            model.resizing = (column, columnWidth(column) / zoom)
                        }
                        let width = max(12, (model.resizing?.startWidth ?? 64) + drag.translation.width / zoom)
                        workbook.sheets[activeSheet].columnWidths[column] = Double(width)
                    }
                    .onEnded { _ in model.resizing = nil }
            )
            #if os(macOS)
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            #endif
    }

    @ViewBuilder
    var pasteSpecialItems: some View {
        Button("Values") { pasteSpecial(.values) }
        Button("Formulas") { pasteSpecial(.formulas) }
        Button("Formatting") { pasteSpecial(.formats) }
        Button("Transpose") { pasteSpecial(.transpose) }
    }

    @ViewBuilder
    private func columnMenu(_ column: Int) -> some View {
        Button("Insert Column Left") { selectColumn(column); insertColumns(right: false) }
        Button("Insert Column Right") { selectColumn(column); insertColumns(right: true) }
        Button("Delete Column") { selectColumn(column); deleteColumns() }
        Divider()
        Button("Hide Column") { selectColumn(column); hideColumns() }
        Button("Unhide Adjacent Columns") { selectColumn(column); unhideColumns() }
        Divider()
        Button("Sort Sheet A to Z by This Column") { sortByColumn(column, ascending: true) }
        Button("Sort Sheet Z to A by This Column") { sortByColumn(column, ascending: false) }
        Divider()
        Button("AutoFit Width") { selectColumn(column); autofitColumns() }
        Button("Reset Width") { selectColumn(column); resetColumnWidths() }
    }

    // MARK: - Find bar

    private var findBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find", text: $model.findText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .focused($focus, equals: .find)
                .onSubmit { findNext() }
            TextField("Replace with", text: $model.replaceText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            Toggle("Match Case", isOn: $model.matchCase)
                .toggleStyle(.button)
            Button("Find Next", action: findNext)
            Button("Replace", action: replaceCurrent)
            Button("Replace All", action: replaceAll)
            Text(model.findStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                model.findVisible = false
                focus = .grid
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Sheet tabs and status

    private var bottomBar: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(workbook.sheets.indices, id: \.self) { index in
                        Text(workbook.sheets[index].name)
                            .font(.system(size: 12, weight: index == activeSheet ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(
                                index == activeSheet ? Color.accentColor.opacity(0.18) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { startRename(index) }
                            .onTapGesture { switchSheet(index) }
                            .contextMenu {
                                Button("Rename…") { startRename(index) }
                                Button("Delete", role: .destructive) { deleteSheet(index) }
                                    .disabled(workbook.sheets.count < 2)
                            }
                    }
                    Button(action: addSheet) { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                        .help("New Sheet")
                }
                .padding(.horizontal, 8)
            }
            if model.painter != nil {
                Text("Click a cell to paste formatting · Esc to cancel")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)
            }
            Text(selectionSummary)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Divider().frame(height: 16)
            Button { setZoom(model.zoom - 0.1) } label: { Image(systemName: "minus") }
                .buttonStyle(.borderless)
                .help("Zoom Out")
            Slider(value: Binding(get: { model.zoom }, set: { setZoom($0) }), in: 0.5...2.5)
                .frame(width: 110)
            Button { setZoom(model.zoom + 0.1) } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless)
                .help("Zoom In")
            Text("\(Int((model.zoom * 100).rounded()))%")
                .font(.system(size: 11).monospacedDigit())
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 10)
        }
        .frame(height: 30)
    }

    /// Sum, average and count of the selected cells, as in Excel's status bar.
    private var selectionSummary: String {
        let range = selection.range
        guard range.cellCount > 1 else { return "" }
        let values = calculator.cells(in: range, sheet: activeSheet)
        let numbers = values.compactMap { cell -> Double? in
            if case .number(let n) = cell.value { return n }
            return nil
        }
        // Quick Calculations, as in Numbers' status bar.
        var parts: [String] = []
        if !numbers.isEmpty {
            let sum = numbers.reduce(0, +)
            parts.append("Sum: " + CellValue.number(sum).displayText)
            parts.append("Average: " + CellValue.number(sum / Double(numbers.count)).displayText)
            parts.append("Min: " + CellValue.number(numbers.min()!).displayText)
            parts.append("Max: " + CellValue.number(numbers.max()!).displayText)
        }
        parts.append("Count: \(values.count)")
        return parts.joined(separator: "   ")
    }

    /// Invisible buttons so shortcuts work whichever ribbon tab is showing.
    private var shortcutButtons: some View {
        Group {
            Button("Bold") { toggle(\.bold, "Bold") }.keyboardShortcut("b")
            Button("Italic") { toggle(\.italic, "Italic") }.keyboardShortcut("i")
            Button("Underline") { toggle(\.underline, "Underline") }.keyboardShortcut("u")
            Button("Fill Down") { fillDown() }.keyboardShortcut("d")
            Button("Fill Right") { fillRight() }.keyboardShortcut("r")
            Button("Find") { showFind() }.keyboardShortcut("f")
            Button("Filter") { toggleFilter() }.keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Currency") { setNumberFormat(NumberFormatPreset.currency.code) }.keyboardShortcut("4", modifiers: [.control, .shift])
            Button("Percent") { setNumberFormat("0%") }.keyboardShortcut("5", modifiers: [.control, .shift])
            Button("Zoom In") { setZoom(model.zoom + 0.1) }.keyboardShortcut("=", modifiers: [.command])
            Button("Zoom Out") { setZoom(model.zoom - 0.1) }.keyboardShortcut("-", modifiers: [.command])
            Button("Insert Date") { insertNow(time: false) }.keyboardShortcut(";", modifiers: [.command])
            Button("Insert Time") { insertNow(time: true) }.keyboardShortcut(";", modifiers: [.command, .shift])
            Button("Format Cells") { showCustomFormat() }.keyboardShortcut("1", modifiers: [.command])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}
