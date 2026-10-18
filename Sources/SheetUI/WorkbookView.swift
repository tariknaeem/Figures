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

    // MARK: - Grid layout

    var rowCount: Int {
        min(CellAddress.maxRows, max(200, (sheet.maxRow ?? 0) + 50, selection.active.row + 30))
    }

    var columnCount: Int {
        min(CellAddress.maxColumns, max(26, (sheet.maxColumn ?? 0) + 5, selection.active.column + 5))
    }

    func columnWidth(_ column: Int) -> CGFloat {
        CGFloat(sheet.columnWidths[column] ?? sheet.defaultColumnWidth) * zoom
    }

    /// Row heights in screen points: the file's height, or one that fits the largest font and wrapped text.
    private func rowHeights(visibleColumns: [Int]) -> [Int: CGFloat] {
        var automatic: [Int: Double] = [:]
        let calc = calculator
        for (address, format) in sheet.formats where sheet.rowHeights[address.row] == nil {
            var points = (format.fontSize ?? workbook.defaultFontSize) * 1.36
            if format.wrapText, sheet.merge(containing: address) == nil {
                let text = calc.displayText(sheet: activeSheet, at: address)
                let size = format.fontSize ?? workbook.defaultFontSize
                let width = (sheet.columnWidths[address.column] ?? sheet.defaultColumnWidth) / Double(Self.pointScale)
                let lines = max(1, (Double(text.count) * size * 0.55 / max(width - 4, 10)).rounded(.up))
                points = max(points, lines * size * 1.3 + 3)
            }
            automatic[address.row] = max(automatic[address.row] ?? 0, points)
        }
        var heights: [Int: CGFloat] = [:]
        for (row, points) in automatic where points > sheet.defaultRowHeight {
            heights[row] = CGFloat(points) * Self.pointScale * zoom
        }
        for (row, points) in sheet.rowHeights {
            heights[row] = CGFloat(points) * Self.pointScale * zoom
        }
        return heights
    }

    /// Where merged areas start and which cells they cover.
    struct MergeMap {
        var areaAt: [CellAddress: CellRange] = [:]
        var originOf: [CellAddress: CellAddress] = [:]

        init(_ merges: [CellRange]) {
            for merge in merges where merge.cellCount <= 20_000 {
                areaAt[merge.start] = merge
                for address in merge.addresses where address != merge.start { originOf[address] = merge.start }
            }
        }
    }

    /// Everything a row needs to draw its cells.
    struct RowContext {
        let calc: Calculator
        let merges: MergeMap
        let columns: [Int]
        let height: (Int) -> CGFloat
        /// Widths of text that overflows into empty cells to its right, by starting column.
        var spill: [Int: CGFloat] = [:]
        /// Columns whose cell lies under overflowing text.
        var spillCovered: Set<Int> = []
    }

    private var grid: some View {
        let calc = calculator
        let hidden = calc.hiddenRows(sheet: activeSheet)
        let rows = rowCount
        let columns = (0..<columnCount).filter { !sheet.hiddenColumns.contains($0) }
        let frozen = min(sheet.frozenRows, rows)
        let heights = rowHeights(visibleColumns: columns)
        let defaultHeight = CGFloat(sheet.defaultRowHeight) * Self.pointScale * zoom
        let height: (Int) -> CGFloat = { heights[$0] ?? defaultHeight }
        let context = RowContext(calc: calc, merges: MergeMap(sheet.merges), columns: columns, height: height)
        let bodyRows = (frozen..<rows).filter { !hidden.contains($0) }
        let frozenRows = (0..<frozen).filter { !hidden.contains($0) }

        return ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(bodyRows, id: \.self) { row in
                            gridRow(row, context)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 0) {
                            columnHeader(columns)
                            ForEach(frozenRows, id: \.self) { row in
                                gridRow(row, context)
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

    private func gridRow(_ row: Int, _ base: RowContext) -> some View {
        let context = spills(row, base)
        let height = context.height(row)
        return HStack(spacing: 0) {
            rowHeader(row, height: height)
            ForEach(context.columns, id: \.self) { column in
                cell(CellAddress(row: row, column: column), height: height, context)
            }
        }
    }

    /// Text in General or left alignment runs into empty cells to the right, as in Excel.
    private func spills(_ row: Int, _ base: RowContext) -> RowContext {
        var context = base
        let columns = base.columns
        var index = 0
        while index < columns.count {
            let address = CellAddress(row: row, column: columns[index])
            index += 1
            guard sheet.cells[address] != nil, base.merges.areaAt[address] == nil, base.merges.originOf[address] == nil else { continue }
            let format = sheet.formats[address] ?? CellFormat()
            guard !format.wrapText, format.alignment == .general || format.alignment == .left,
                  case .text(let text) = base.calc.value(sheet: activeSheet, at: address) else { continue }
            let fontSize = CGFloat(format.fontSize ?? workbook.defaultFontSize) * Self.pointScale * zoom
            let needed = CGFloat(text.count) * fontSize * 0.56 + 8 * zoom + CGFloat(format.indent) * 9 * zoom
            var total = columnWidth(address.column)
            var next = index
            while total < needed, next < columns.count, next - index < 12 {
                let neighbor = CellAddress(row: row, column: columns[next])
                guard sheet.cells[neighbor] == nil, base.merges.areaAt[neighbor] == nil,
                      base.merges.originOf[neighbor] == nil else { break }
                total += columnWidth(neighbor.column)
                context.spillCovered.insert(neighbor.column)
                next += 1
            }
            if next > index { context.spill[address.column] = total }
            index = next
        }
        return context
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

    private func rowHeader(_ row: Int, height: CGFloat) -> some View {
        let selected = (selection.range.start.row...selection.range.end.row).contains(row)
        let filtered = sheet.filter?.allowedValues.isEmpty == false && sheet.filter?.dataRows?.contains(row) == true
        return Text(String(row + 1))
            .font(.system(size: 11 * zoom, weight: selected ? .semibold : .regular).monospacedDigit())
            .foregroundStyle(filtered ? Color.accentColor : Color(white: 0.35))
            .frame(width: Self.rowHeaderWidth, height: height)
            .background(selected ? Color.accentColor.opacity(0.18) : Self.headerBackground)
            .overlay(headerLine)
            .contentShape(Rectangle())
            .onTapGesture { selectRow(row) }
            .contextMenu { rowMenu(row) }
            .overlay(alignment: .bottom) { rowResizeHandle(row, height: height) }
    }

    private func rowResizeHandle(_ row: Int, height: CGFloat) -> some View {
        Color.clear
            .frame(height: 6)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        if model.resizingRow?.row != row { model.resizingRow = (row, height) }
                        let screen = max(6, (model.resizingRow?.startHeight ?? height) + drag.translation.height)
                        workbook.sheets[activeSheet].rowHeights[row] = Double(screen / (Self.pointScale * zoom))
                    }
                    .onEnded { _ in model.resizingRow = nil }
            )
            #if os(macOS)
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            #endif
    }

    // MARK: - Cells

    @ViewBuilder
    private func cell(_ address: CellAddress, height: CGFloat, _ context: RowContext) -> some View {
        let width = columnWidth(address.column)
        let inRange = selection.range.cellCount > 1 && selection.range.contains(address)
        if context.merges.originOf[address] != nil {
            // Covered by a merged area that the top-left cell draws; stays transparent but clickable.
            Color.clear
                .frame(width: width, height: height)
                .overlay(inRange ? Color.accentColor.opacity(0.14) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { cellTapped(address) }
                .contextMenu { cellMenu }
                .id(address)
        } else {
            let merge = context.merges.areaAt[address]
            let faceWidth = merge.map { mergedWidth($0) } ?? width
            let faceHeight = merge.map { mergedHeight($0, context.height) } ?? height
            Color.clear
                .frame(width: width, height: height)
                .overlay(alignment: .topLeading) {
                    face(address, width: faceWidth, height: faceHeight, context: context)
                }
                .contentShape(Rectangle())
                .onTapGesture { cellTapped(address) }
                .contextMenu { cellMenu }
                .id(address)
        }
    }

    private func mergedWidth(_ merge: CellRange) -> CGFloat {
        (merge.start.column...merge.end.column).filter { !sheet.hiddenColumns.contains($0) }.reduce(0) { $0 + columnWidth($1) }
    }

    private func mergedHeight(_ merge: CellRange, _ height: (Int) -> CGFloat) -> CGFloat {
        let hidden = calculator.hiddenRows(sheet: activeSheet)
        return (merge.start.row...merge.end.row).filter { !hidden.contains($0) }.reduce(0) { $0 + height($1) }
    }

    /// What a cell (or merged area) shows: fill, conditional formatting, text, gridlines, borders and selection.
    @ViewBuilder
    private func face(_ address: CellAddress, width: CGFloat, height: CGFloat, context: RowContext) -> some View {
        let format = sheet.formats[address] ?? CellFormat()
        let isActive = selection.active == address
        let inRange = selection.range.cellCount > 1 && selection.range.contains(address)
        let spillCovered = context.spillCovered.contains(address.column)
        let spill = context.spill[address.column]
        let rightLine = spill == nil && !(spillCovered && context.spillCovered.contains(nextVisibleColumn(after: address.column, context)))
        let lines = sheet.showGridlines

        if let editor, editor.inCell, editor.address == address {
            TextField("", text: cellEditorText)
                .textFieldStyle(.plain)
                .font(font(for: format, conditional: nil))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 3 * zoom)
                .frame(width: max(width, 120 * zoom), height: height)
                .background(Color.white)
                .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 2))
                .focused($focus, equals: .cellEditor)
                .onSubmit { commitEdit(moveRows: 1, moveColumns: 0) }
                .onKeyPress(.tab) {
                    let assist = FormulaAssist(text: editor.text)
                    if let first = assist.suggestions.first {
                        acceptSuggestion(first.name, replacing: assist.prefix)
                    } else {
                        commitEdit(moveRows: 0, moveColumns: 1)
                    }
                    return .handled
                }
                .onKeyPress(.escape) {
                    cancelEdit()
                    return .handled
                }
                #if os(macOS)
                .onExitCommand { cancelEdit() }
                #endif
        } else {
            let value = context.calc.value(sheet: activeSheet, at: address)
            let conditional = context.calc.conditionalFormatting(sheet: activeSheet, at: address)
            let shown = model.showFormulas
                ? FormattedValue(text: sheet.cells[address] ?? "", color: nil)
                : ExcelNumberFormat.format(value, code: format.numberFormat)
            let fill = conditional?.scaleColor ?? conditional?.style.fillColor ?? format.fillColor
            let textColor = conditional?.style.textColor ?? shown.color ?? format.textColor
            let textAlignment = alignment(for: format, value: value)
            let textWidth = spill ?? width

            ZStack(alignment: .topLeading) {
                (fill.map { Color($0) } ?? Color.clear)
                    .frame(width: width, height: height)
                if let bar = conditional?.dataBar {
                    LinearGradient(colors: [Color(bar.color), Color(bar.color).opacity(0.3)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: max(0, (width - 4) * bar.fraction), height: max(0, height - 4))
                        .offset(x: 2, y: 2)
                }
                Text(shown.text)
                    .font(font(for: format, conditional: conditional?.style))
                    .underline(conditional?.style.underline ?? format.underline)
                    .strikethrough(conditional?.style.strikethrough ?? format.strikethrough)
                    .foregroundStyle(textColor.map { Color($0) } ?? Color.black)
                    .lineLimit(format.wrapText ? nil : 1)
                    .multilineTextAlignment(textAlignment.horizontal == .trailing ? .trailing : (textAlignment.horizontal == .center ? .center : .leading))
                    .fixedSize(horizontal: false, vertical: format.wrapText)
                    .padding(.leading, (3 + CGFloat(format.indent) * 9) * zoom)
                    .padding(.trailing, 3 * zoom)
                    .frame(width: textWidth, height: height, alignment: textAlignment)
                    .clipped()
            }
            .frame(width: width, height: height, alignment: .topLeading)
            .overlay(alignment: .bottom) {
                if lines { Rectangle().fill(Self.gridColor).frame(height: 0.5) }
            }
            .overlay(alignment: .trailing) {
                if lines && rightLine { Rectangle().fill(Self.gridColor).frame(width: 0.5) }
            }
            .overlay {
                if !format.border.isEmpty { CellBorderLines(border: format.border, scale: zoom) }
            }
            .overlay(inRange ? Color.accentColor.opacity(0.14) : Color.clear)
            .overlay {
                if isActive { Rectangle().stroke(Color.accentColor, lineWidth: 2) }
            }
            .overlay(alignment: .trailing) {
                if isFilterHeader(address) { filterButton(address.column) }
            }
        }
    }

    private func nextVisibleColumn(after column: Int, _ context: RowContext) -> Int {
        guard let index = context.columns.firstIndex(of: column), index + 1 < context.columns.count else { return -1 }
        return context.columns[index + 1]
    }

    func font(for format: CellFormat, conditional: DifferentialStyle?) -> Font {
        let size = CGFloat(format.fontSize ?? workbook.defaultFontSize) * Self.pointScale * zoom
        var font = Font.custom(format.fontName ?? workbook.defaultFontName, size: size)
        if conditional?.bold ?? format.bold { font = font.bold() }
        if conditional?.italic ?? format.italic { font = font.italic() }
        return font
    }

    private func alignment(for format: CellFormat, value: CellValue) -> Alignment {
        let horizontal: HorizontalAlignment
        switch format.alignment {
        case .left: horizontal = .leading
        case .center: horizontal = .center
        case .right: horizontal = .trailing
        case .general:
            switch value {
            case .number: horizontal = .trailing
            case .boolean, .error: horizontal = .center
            case .empty, .text: horizontal = .leading
            }
        }
        let vertical: VerticalAlignment = switch format.verticalAlignment {
        case .top: .top
        case .center: .center
        case .bottom: .bottom
        }
        return Alignment(horizontal: horizontal, vertical: vertical)
    }

    // MARK: - Filter dropdowns

    private func isFilterHeader(_ address: CellAddress) -> Bool {
        guard let filter = sheet.filter else { return false }
        return address.row == filter.range.start.row
            && (filter.range.start.column...filter.range.end.column).contains(address.column)
    }

    private func filterButton(_ column: Int) -> some View {
        let active = sheet.filter?.allowedValues[column] != nil
        return Button { model.filterColumn = column } label: {
            Image(systemName: active ? "line.3.horizontal.decrease.circle.fill" : "chevron.down.square")
                .font(.system(size: 12 * zoom))
                .foregroundStyle(active ? Color.accentColor : Color.gray)
                .padding(.trailing, 3)
        }
        .buttonStyle(.plain)
        .help(active ? "Filtered" : "Filter")
        .popover(isPresented: Binding(get: { model.filterColumn == column }, set: { if !$0 { model.filterColumn = nil } })) {
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
    }

    // MARK: - Context menus

    @ViewBuilder
    private var cellMenu: some View {
        Button("Cut") { _ = cutSelection() }
        Button("Copy") { _ = copySelection() }
        Button("Paste") { pasteFromSystem() }
        Menu("Paste Special") { pasteSpecialItems }
        Divider()
        Menu("Insert") {
            Button("Rows Above") { insertRows(below: false) }
            Button("Rows Below") { insertRows(below: true) }
            Button("Columns Left") { insertColumns(right: false) }
            Button("Columns Right") { insertColumns(right: true) }
        }
        Menu("Delete") {
            Button("Rows") { deleteRows() }
            Button("Columns") { deleteColumns() }
        }
        Button("Clear Contents") { clearSelection() }
        Divider()
        Button("Sort A to Z") { sortSelection(ascending: true) }
        Button("Sort Z to A") { sortSelection(ascending: false) }
        Button("Filter by Selected Cell's Value") { filterBySelectedValue() }
        Divider()
        Button("Merge & Center") { mergeSelection(center: true, across: false) }
        Button("Unmerge Cells") { unmergeSelection() }
        Button("Format Cells…") { showCustomFormat() }
    }

    @ViewBuilder
    var pasteSpecialItems: some View {
        Button("Values") { pasteSpecial(.values) }
        Button("Formulas") { pasteSpecial(.formulas) }
        Button("Formatting") { pasteSpecial(.formats) }
        Button("Transpose") { pasteSpecial(.transpose) }
    }

    @ViewBuilder
    private func rowMenu(_ row: Int) -> some View {
        Button("Insert Row Above") { selectRow(row); insertRows(below: false) }
        Button("Insert Row Below") { selectRow(row); insertRows(below: true) }
        Button("Delete Row") { selectRow(row); deleteRows() }
        Divider()
        Button("Hide Row") { selectRow(row); hideRows() }
        Button("Unhide Adjacent Rows") { selectRow(row); unhideRows() }
        Button("AutoFit Row Height") { selectRow(row); autofitRows() }
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
        var parts: [String] = []
        if !numbers.isEmpty {
            let sum = numbers.reduce(0, +)
            parts.append("Average: " + CellValue.number(sum / Double(numbers.count)).displayText)
            parts.append("Sum: " + CellValue.number(sum).displayText)
        }
        parts.append("Count: \(values.count)")
        return parts.joined(separator: "    ")
    }

    /// Invisible buttons so shortcuts work whichever ribbon tab is showing.
    private var shortcutButtons: some View {
        Group {
            Button("Bold") { toggle(\.bold, "Bold") }.keyboardShortcut("b")
            Button("Italic") { toggle(\.italic, "Italic") }.keyboardShortcut("i")
            Button("Underline") { toggle(\.underline, "Underline") }.keyboardShortcut("u")
            Button("Fill Down") { fillDown() }.keyboardShortcut("d")
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
