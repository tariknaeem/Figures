import SheetCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

// The grid is drawn from plain values: a row is redrawn only when its values or its share of the
// selection change, so moving the selection redraws two rows instead of the whole sheet.

struct FontSpec: Hashable {
    var name: String
    var size: CGFloat
    var bold: Bool
    var italic: Bool

    var font: Font {
        var font = Font.custom(name, size: size)
        if bold { font = font.bold() }
        if italic { font = font.italic() }
        return font
    }
}

/// An interactive control as a cell shows it.
enum ControlFace: Equatable {
    case checkbox(Bool)
    case rating(Int)
    case popUp([String])
    case stepper(value: Double, step: Double)
    case slider(value: Double, minimum: Double, maximum: Double, step: Double)
}

/// What one cell, or the merged area it starts, shows.
struct CellFace: Equatable {
    var width: CGFloat
    var height: CGFloat
    /// Wider than `width` when text overflows into empty cells to the right.
    var textWidth: CGFloat
    var text: String
    var font: FontSpec
    var textColor: SheetCore.RGBColor?
    var fill: SheetCore.RGBColor?
    var dataBar: DataBar?
    var border: CellBorder
    var alignment: Alignment
    var wrap: Bool
    var indent: Int
    var underline: Bool
    var strikethrough: Bool
    var filterHeader: Bool
    var filterActive: Bool
    var control: ControlFace?

    static func == (a: CellFace, b: CellFace) -> Bool {
        a.width == b.width && a.height == b.height && a.textWidth == b.textWidth && a.text == b.text && a.font == b.font
            && a.textColor == b.textColor && a.fill == b.fill && a.dataBar == b.dataBar && a.border == b.border
            && a.alignment.horizontal == b.alignment.horizontal && a.alignment.vertical == b.alignment.vertical
            && a.wrap == b.wrap && a.indent == b.indent && a.underline == b.underline && a.strikethrough == b.strikethrough
            && a.filterHeader == b.filterHeader && a.filterActive == b.filterActive && a.control == b.control
    }
}

struct CellRender: Equatable {
    let column: Int
    let width: CGFloat
    /// nil for cells covered by another cell's merged area.
    let face: CellFace?
}

struct GridLine: Equatable {
    let from: CGPoint
    let to: CGPoint
}

struct RowRender: Equatable {
    let row: Int
    let height: CGFloat
    let width: CGFloat
    let cells: [CellRender]
    /// Gridline segments in row coordinates, leaving out lines inside merges and under overflowing text.
    let lines: [GridLine]
}

/// The selection as one row sees it.
struct RowSelection: Equatable {
    var activeColumn: Int?
    var rangeColumns: ClosedRange<Int>?
    var headerSelected = false
    /// The column whose cell carries the fill handle, at the selection's bottom-right corner.
    var handleColumn: Int?
    /// Columns an autofill drag is about to fill.
    var fillColumns: ClosedRange<Int>?
}

enum GridCommand {
    case tap(CellAddress)
    case cut, copy, paste, pasteSpecial(PasteSpecial)
    case insertRows(below: Bool), insertColumns(right: Bool), deleteRows, deleteColumns, clearContents
    case sort(ascending: Bool), filterBySelection, merge, unmerge, formatCells
    case openFilter(Int), closeFilter
    case selectRow(Int), rowMenu(RowMenuCommand, Int)
    case resizeRow(Int, startHeight: CGFloat, translation: CGFloat), endRowResize
    case commitEdit(rows: Int, columns: Int), cancelEdit, editorTab
    case setControl(CellAddress, CellValue)
    case fillDrag(CGSize), fillEnd
}

enum RowMenuCommand {
    case insertAbove, insertBelow, delete, hide, unhide, autofit
}

/// Callbacks and bindings from the window, kept out of row equality.
final class GridActions {
    var perform: (GridCommand) -> Void = { _ in }
    var editorText: Binding<String> = .constant("")
    var filterPopover: (Int) -> AnyView = { _ in AnyView(EmptyView()) }
}

/// Layout and appearance of a sheet, computed once per workbook version and reused while scrolling,
/// selecting and typing.
final class GridLayout {
    struct Key: Equatable {
        let version: UUID
        let sheet: Int
        let zoom: Double
        let showFormulas: Bool
        let columnCount: Int
    }

    let key: Key
    let columns: [Int]
    let hidden: Set<Int>
    private let sheet: Sheet
    private let sheetIndex: Int
    private let calc: Calculator
    private let defaultFont: (name: String, size: Double)
    private let zoom: CGFloat
    private let defaultHeight: CGFloat
    private let heights: [Int: CGFloat]
    private let widths: [Int: CGFloat]
    private let mergeAt: [CellAddress: CellRange]
    private let coveredBy: [CellAddress: CellAddress]
    private let filterHeaderRow: Int?
    private var rows: [Int: RowRender] = [:]

    init(key: Key, workbook: Workbook, calculator: Calculator) {
        self.key = key
        let sheet = workbook.sheets[key.sheet]
        self.sheet = sheet
        sheetIndex = key.sheet
        calc = calculator
        defaultFont = (workbook.defaultFontName, workbook.defaultFontSize)
        zoom = CGFloat(key.zoom)
        columns = (0..<key.columnCount).filter { !sheet.hiddenColumns.contains($0) }
        hidden = calculator.hiddenRows(sheet: key.sheet)
        let scale = WorkbookView.pointScale * CGFloat(key.zoom)
        defaultHeight = CGFloat(sheet.defaultRowHeight) * scale
        var widths: [Int: CGFloat] = [:]
        for column in columns { widths[column] = CGFloat(sheet.columnWidths[column] ?? sheet.defaultColumnWidth) * CGFloat(key.zoom) }
        self.widths = widths

        // Rows without a fixed height grow to fit their largest font and wrapped text.
        var automatic: [Int: Double] = [:]
        for (address, format) in sheet.formats where sheet.rowHeights[address.row] == nil {
            let size = format.fontSize ?? workbook.defaultFontSize
            var points = size * 1.36
            if format.wrapText, sheet.merge(containing: address) == nil {
                let text = calculator.displayText(sheet: key.sheet, at: address)
                let width = (sheet.columnWidths[address.column] ?? sheet.defaultColumnWidth) / Double(WorkbookView.pointScale)
                let lines = max(1, (Double(text.count) * size * 0.55 / max(width - 4, 10)).rounded(.up))
                points = max(points, lines * size * 1.3 + 3)
            }
            automatic[address.row] = max(automatic[address.row] ?? 0, points)
        }
        var heights: [Int: CGFloat] = [:]
        for (row, points) in automatic where points > sheet.defaultRowHeight { heights[row] = CGFloat(points) * scale }
        for (row, points) in sheet.rowHeights { heights[row] = CGFloat(points) * scale }
        self.heights = heights

        var mergeAt: [CellAddress: CellRange] = [:]
        var coveredBy: [CellAddress: CellAddress] = [:]
        for merge in sheet.merges where merge.cellCount <= 20_000 {
            mergeAt[merge.start] = merge
            for address in merge.addresses where address != merge.start { coveredBy[address] = merge.start }
        }
        self.mergeAt = mergeAt
        self.coveredBy = coveredBy
        filterHeaderRow = sheet.filter?.range.start.row
    }

    func width(_ column: Int) -> CGFloat { widths[column] ?? CGFloat(sheet.defaultColumnWidth) * zoom }
    func height(_ row: Int) -> CGFloat { heights[row] ?? defaultHeight }
    func merge(at address: CellAddress) -> CellRange? { mergeAt[address] }

    func row(_ row: Int) -> RowRender {
        if let cached = rows[row] { return cached }
        let render = build(row)
        rows[row] = render
        return render
    }

    private func build(_ row: Int) -> RowRender {
        let height = height(row)
        var spill: [Int: CGFloat] = [:]
        var spillCovered: Set<Int> = []

        // Text in General or left alignment runs into empty cells to the right, as in Excel.
        var index = 0
        while index < columns.count {
            let address = CellAddress(row: row, column: columns[index])
            index += 1
            guard sheet.cells[address] != nil, mergeAt[address] == nil, coveredBy[address] == nil else { continue }
            let format = sheet.formats[address] ?? CellFormat()
            guard !format.wrapText, format.alignment == .general || format.alignment == .left,
                  case .text(let text) = calc.value(sheet: sheetIndex, at: address) else { continue }
            let fontSize = CGFloat(format.fontSize ?? defaultFont.size) * WorkbookView.pointScale * zoom
            let needed = CGFloat(text.count) * fontSize * 0.56 + 8 * zoom + CGFloat(format.indent) * 9 * zoom
            var total = width(address.column)
            var next = index
            while total < needed, next < columns.count, next - index < 12 {
                let neighbor = CellAddress(row: row, column: columns[next])
                guard sheet.cells[neighbor] == nil, mergeAt[neighbor] == nil, coveredBy[neighbor] == nil else { break }
                total += width(neighbor.column)
                spillCovered.insert(neighbor.column)
                next += 1
            }
            if next > index { spill[address.column] = total }
            index = next
        }

        var cells: [CellRender] = []
        var lines: [GridLine] = []
        var x: CGFloat = 0
        for (position, column) in columns.enumerated() {
            let address = CellAddress(row: row, column: column)
            let width = width(column)
            let nextColumn = position + 1 < columns.count ? columns[position + 1] : -1
            var bottom = true
            var right = true
            if let origin = coveredBy[address], let merge = mergeAt[origin] {
                bottom = row == merge.end.row
                right = column == merge.end.column
                cells.append(CellRender(column: column, width: width, face: nil))
            } else {
                if let merge = mergeAt[address] {
                    bottom = row == merge.end.row
                    right = column == merge.end.column
                }
                if spill[column] != nil || (spillCovered.contains(column) && spillCovered.contains(nextColumn)) { right = false }
                cells.append(CellRender(column: column, width: width, face: face(address, width: width, height: height, spill: spill[column])))
            }
            if sheet.showGridlines {
                if bottom { lines.append(GridLine(from: CGPoint(x: x, y: height - 0.25), to: CGPoint(x: x + width, y: height - 0.25))) }
                if right { lines.append(GridLine(from: CGPoint(x: x + width - 0.25, y: 0), to: CGPoint(x: x + width - 0.25, y: height))) }
            }
            x += width
        }
        return RowRender(row: row, height: height, width: x, cells: cells, lines: lines)
    }

    private func face(_ address: CellAddress, width: CGFloat, height: CGFloat, spill: CGFloat?) -> CellFace {
        let format = sheet.formats[address] ?? CellFormat()
        let value = calc.value(sheet: sheetIndex, at: address)
        let conditional = calc.conditionalFormatting(sheet: sheetIndex, at: address)
        let shown = key.showFormulas
            ? FormattedValue(text: sheet.cells[address] ?? "", color: nil)
            : ExcelNumberFormat.format(value, code: format.numberFormat)

        var faceWidth = width
        var faceHeight = height
        if let merge = mergeAt[address] {
            faceWidth = (merge.start.column...merge.end.column).filter { !sheet.hiddenColumns.contains($0) }.reduce(0) { $0 + self.width($1) }
            faceHeight = (merge.start.row...merge.end.row).filter { !hidden.contains($0) }.reduce(0) { $0 + self.height($1) }
        }

        let horizontal: HorizontalAlignment
        switch format.alignment {
        case .left: horizontal = .leading
        case .center: horizontal = .center
        case .right: horizontal = .trailing
        case .general:
            switch value {
            case .number: horizontal = key.showFormulas ? .leading : .trailing
            case .boolean, .error: horizontal = .center
            case .empty, .text: horizontal = .leading
            }
        }
        let vertical: VerticalAlignment = switch format.verticalAlignment {
        case .top: .top
        case .center: .center
        case .bottom: .bottom
        }
        let filter = sheet.filter
        let isFilterHeader = filterHeaderRow == address.row && filter.map { (($0.range.start.column)...($0.range.end.column)).contains(address.column) } == true

        return CellFace(
            width: faceWidth, height: faceHeight, textWidth: spill ?? faceWidth,
            text: shown.text,
            font: FontSpec(name: format.fontName ?? defaultFont.name,
                           size: CGFloat(format.fontSize ?? defaultFont.size) * WorkbookView.pointScale * zoom,
                           bold: conditional?.style.bold ?? format.bold, italic: conditional?.style.italic ?? format.italic),
            textColor: conditional?.style.textColor ?? shown.color ?? format.textColor,
            fill: conditional?.scaleColor ?? conditional?.style.fillColor ?? format.fillColor,
            dataBar: conditional?.dataBar,
            border: format.border,
            alignment: Alignment(horizontal: horizontal, vertical: vertical),
            wrap: format.wrapText, indent: format.indent,
            underline: conditional?.style.underline ?? format.underline,
            strikethrough: conditional?.style.strikethrough ?? format.strikethrough,
            filterHeader: isFilterHeader,
            filterActive: isFilterHeader && filter?.allowedValues[address.column] != nil,
            control: controlFace(sheet.controls[address], value: value)
        )
    }

    private func controlFace(_ control: CellControl?, value: CellValue) -> ControlFace? {
        guard let control, !key.showFormulas else { return nil }
        let number = value.numberValue ?? 0
        switch control {
        case .checkbox: return .checkbox(value.isTrue)
        case .rating: return .rating(Int(min(5, max(0, number.rounded()))))
        case .popUp(let source): return .popUp(calc.popUpOptions(source, sheet: sheetIndex))
        case .stepper(_, _, let step): return .stepper(value: number, step: step)
        case .slider(let low, let high, let step): return .slider(value: number, minimum: low, maximum: max(high, low + step), step: step)
        }
    }
}

// MARK: - Views

struct RowView: View, Equatable {
    let render: RowRender
    let selection: RowSelection
    let filtered: Bool
    /// The in-cell editor, when it is in this row.
    let editor: CellEditor?
    let openFilterColumn: Int?
    let zoom: CGFloat
    let actions: GridActions
    let focus: FocusState<FocusField?>.Binding

    static func == (a: RowView, b: RowView) -> Bool {
        a.render == b.render && a.selection == b.selection && a.filtered == b.filtered && a.editor == b.editor
            && a.openFilterColumn == b.openFilterColumn && a.zoom == b.zoom
    }

    var body: some View {
        HStack(spacing: 0) {
            RowHeaderView(row: render.row, height: render.height, selected: selection.headerSelected,
                          filtered: filtered, zoom: zoom, actions: actions)
            HStack(spacing: 0) {
                ForEach(render.cells, id: \.column) { cell in
                    CellView(cell: cell, address: CellAddress(row: render.row, column: cell.column), height: render.height,
                             isActive: selection.activeColumn == cell.column,
                             inRange: selection.rangeColumns?.contains(cell.column) == true,
                             hasHandle: selection.handleColumn == cell.column,
                             inFillPreview: selection.fillColumns?.contains(cell.column) == true,
                             editor: editor?.address.column == cell.column ? editor : nil,
                             filterOpen: openFilterColumn == cell.column,
                             zoom: zoom, actions: actions, focus: focus)
                }
            }
            .background(alignment: .topLeading) { GridLinesView(lines: render.lines) }
        }
    }
}

struct GridLinesView: View {
    let lines: [GridLine]

    var body: some View {
        Canvas { context, _ in
            var path = Path()
            for line in lines {
                path.move(to: line.from)
                path.addLine(to: line.to)
            }
            context.stroke(path, with: .color(WorkbookView.gridColor), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

struct RowHeaderView: View {
    let row: Int
    let height: CGFloat
    let selected: Bool
    let filtered: Bool
    let zoom: CGFloat
    let actions: GridActions

    var body: some View {
        Text(String(row + 1))
            .font(.system(size: 11 * zoom, weight: selected ? .semibold : .regular).monospacedDigit())
            .foregroundStyle(filtered || selected ? WorkbookView.accent : WorkbookView.headerText)
            .frame(width: WorkbookView.rowHeaderWidth, height: height)
            .background(selected ? WorkbookView.accent.opacity(0.13) : WorkbookView.headerBackground)
            .overlay(Rectangle().stroke(WorkbookView.gridColor, lineWidth: 0.5))
            .contentShape(Rectangle())
            .onTapGesture { actions.perform(.selectRow(row)) }
            .contextMenu {
                Button("Insert Row Above") { actions.perform(.rowMenu(.insertAbove, row)) }
                Button("Insert Row Below") { actions.perform(.rowMenu(.insertBelow, row)) }
                Button("Delete Row") { actions.perform(.rowMenu(.delete, row)) }
                Divider()
                Button("Hide Row") { actions.perform(.rowMenu(.hide, row)) }
                Button("Unhide Adjacent Rows") { actions.perform(.rowMenu(.unhide, row)) }
                Button("AutoFit Row Height") { actions.perform(.rowMenu(.autofit, row)) }
            }
            .overlay(alignment: .bottom) {
                Color.clear
                    .frame(height: 6)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { actions.perform(.resizeRow(row, startHeight: height, translation: $0.translation.height)) }
                            .onEnded { _ in actions.perform(.endRowResize) }
                    )
                    #if os(macOS)
                    .onHover { inside in
                        if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                    }
                    #endif
            }
    }
}

struct CellView: View {
    let cell: CellRender
    let address: CellAddress
    let height: CGFloat
    let isActive: Bool
    let inRange: Bool
    let hasHandle: Bool
    let inFillPreview: Bool
    let editor: CellEditor?
    let filterOpen: Bool
    let zoom: CGFloat
    let actions: GridActions
    let focus: FocusState<FocusField?>.Binding

    var body: some View {
        Color.clear
            .frame(width: cell.width, height: height)
            .overlay(alignment: .topLeading) {
                if let face = cell.face {
                    if editor != nil {
                        editorField(face)
                    } else {
                        faceView(face)
                    }
                }
            }
            .overlay {
                if inRange { WorkbookView.accent.opacity(0.11).allowsHitTesting(false) }
                if inFillPreview { Color.gray.opacity(0.18).allowsHitTesting(false) }
            }
            .overlay(alignment: .bottomTrailing) {
                if hasHandle { fillHandle }
            }
            .contentShape(Rectangle())
            .onTapGesture { actions.perform(.tap(address)) }
            .contextMenu { CellMenu(actions: actions) }
            .id(address)
    }

    @ViewBuilder
    private func faceView(_ face: CellFace) -> some View {
        ZStack(alignment: .topLeading) {
            if let fill = face.fill {
                Color(fill).frame(width: face.width, height: face.height)
            }
            if let bar = face.dataBar {
                LinearGradient(colors: [Color(bar.color).opacity(0.55), Color(bar.color).opacity(0.12)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: max(0, (face.width - 4) * bar.fraction), height: max(0, face.height - 4))
                    .offset(x: 2, y: 2)
            }
            if let control = face.control {
                controlView(face, control)
            } else if !face.text.isEmpty {
                Text(face.text)
                    .font(face.font.font)
                    .underline(face.underline)
                    .strikethrough(face.strikethrough)
                    .foregroundStyle(face.textColor.map { Color($0) } ?? Color.black)
                    .lineLimit(face.wrap ? nil : 1)
                    .multilineTextAlignment(face.alignment.horizontal == .trailing ? .trailing : (face.alignment.horizontal == .center ? .center : .leading))
                    .fixedSize(horizontal: false, vertical: face.wrap)
                    .padding(.leading, (3 + CGFloat(face.indent) * 9) * zoom)
                    .padding(.trailing, 3 * zoom)
                    .frame(width: face.textWidth, height: face.height, alignment: face.alignment)
                    .clipped()
                    .allowsHitTesting(false)
            }
            if !face.border.isEmpty {
                CellBorderLines(border: face.border, scale: zoom).frame(width: face.width, height: face.height)
            }
            if isActive {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(WorkbookView.accent, lineWidth: 2)
                    .frame(width: face.width, height: face.height)
            }
        }
        .frame(width: face.width, height: face.height, alignment: .topLeading)
        .overlay(alignment: .trailing) {
            if face.filterHeader { filterButton(face) }
        }
    }

    /// The small square at the selection's corner; drag it to extend a series.
    private var fillHandle: some View {
        Rectangle()
            .fill(WorkbookView.accent)
            .overlay(Rectangle().stroke(Color.white, lineWidth: 1))
            .frame(width: 7, height: 7)
            .offset(x: 3, y: 3)
            .contentShape(Rectangle().inset(by: -4))
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { actions.perform(.fillDrag($0.translation)) }
                    .onEnded { _ in actions.perform(.fillEnd) }
            )
            #if os(macOS)
            .onHover { inside in
                if inside { NSCursor.crosshair.push() } else { NSCursor.pop() }
            }
            #endif
            .help("Drag to fill")
    }

    private func set(_ value: CellValue) {
        actions.perform(.setControl(address, value))
    }

    @ViewBuilder
    private func controlView(_ face: CellFace, _ control: ControlFace) -> some View {
        let iconSize = 13 * zoom
        switch control {
        case .checkbox(let on):
            Button { set(.boolean(!on)) } label: {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: iconSize))
                    .foregroundStyle(on ? WorkbookView.accent : Color.gray)
                    .padding(.horizontal, 4 * zoom)
            }
            .buttonStyle(.plain)
            .frame(width: face.width, height: face.height,
                   alignment: Alignment(horizontal: face.alignment.horizontal == .trailing ? .trailing
                                            : (face.alignment.horizontal == .leading ? .leading : .center), vertical: .center))
        case .rating(let stars):
            HStack(spacing: 1) {
                ForEach(1...5, id: \.self) { star in
                    Button { set(.number(Double(star == stars ? star - 1 : star))) } label: {
                        Image(systemName: star <= stars ? "star.fill" : "star")
                            .font(.system(size: 11 * zoom))
                            .foregroundStyle(star <= stars ? Color.orange : Color.gray.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4 * zoom)
            .frame(width: face.width, height: face.height, alignment: .leading)
        case .popUp(let options):
            HStack(spacing: 2) {
                Text(face.text)
                    .font(face.font.font)
                    .foregroundStyle(face.textColor.map { Color($0) } ?? Color.black)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Menu {
                    ForEach(options, id: \.self) { option in
                        Button(option) { set(.text(option)) }
                    }
                    Divider()
                    Button("None") { set(.empty) }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9 * zoom, weight: .semibold))
                        .foregroundStyle(Color.gray)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 4 * zoom)
            .frame(width: face.width, height: face.height)
        case .stepper(let value, let step):
            HStack(spacing: 3) {
                Text(face.text)
                    .font(face.font.font)
                    .foregroundStyle(face.textColor.map { Color($0) } ?? Color.black)
                    .lineLimit(1)
                Spacer(minLength: 0)
                ForEach([("minus", -step), ("plus", step)], id: \.0) { symbol, delta in
                    Button { set(.number(value + delta)) } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 8 * zoom, weight: .bold))
                            .frame(width: 14 * zoom, height: 14 * zoom)
                            .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4 * zoom)
            .frame(width: face.width, height: face.height)
        case .slider(let value, let low, let high, let step):
            HStack(spacing: 4) {
                Slider(value: Binding(get: { value }, set: { set(.number(($0 / step).rounded() * step)) }), in: low...high)
                    .controlSize(.mini)
                Text(face.text)
                    .font(face.font.font)
                    .foregroundStyle(Color.black)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 4 * zoom)
            .frame(width: face.width, height: face.height)
        }
    }

    private func filterButton(_ face: CellFace) -> some View {
        Button { actions.perform(.openFilter(address.column)) } label: {
            Image(systemName: face.filterActive ? "line.3.horizontal.decrease.circle.fill" : "chevron.down.square")
                .font(.system(size: 12 * zoom))
                .foregroundStyle(face.filterActive ? WorkbookView.accent : Color.gray)
                .padding(.trailing, 3)
        }
        .buttonStyle(.plain)
        .help(face.filterActive ? "Filtered" : "Filter")
        .popover(isPresented: Binding(get: { filterOpen }, set: { if !$0 { actions.perform(.closeFilter) } })) {
            actions.filterPopover(address.column)
        }
    }

    private func editorField(_ face: CellFace) -> some View {
        TextField("", text: actions.editorText)
            .textFieldStyle(.plain)
            .font(FontSpec(name: face.font.name, size: face.font.size, bold: false, italic: false).font)
            .foregroundStyle(Color.black)
            .padding(.horizontal, 3 * zoom)
            .frame(width: max(face.width, 120 * zoom), height: face.height)
            .background(Color.white)
            .overlay(Rectangle().stroke(WorkbookView.accent, lineWidth: 2))
            .focused(focus, equals: .cellEditor)
            .onSubmit { actions.perform(.commitEdit(rows: 1, columns: 0)) }
            .onKeyPress(.tab) {
                actions.perform(.editorTab)
                return .handled
            }
            .onKeyPress(.escape) {
                actions.perform(.cancelEdit)
                return .handled
            }
            #if os(macOS)
            .onExitCommand { actions.perform(.cancelEdit) }
            #endif
    }
}

struct CellMenu: View {
    let actions: GridActions

    var body: some View {
        Button("Cut") { actions.perform(.cut) }
        Button("Copy") { actions.perform(.copy) }
        Button("Paste") { actions.perform(.paste) }
        Menu("Paste Special") {
            Button("Values") { actions.perform(.pasteSpecial(.values)) }
            Button("Formulas") { actions.perform(.pasteSpecial(.formulas)) }
            Button("Formatting") { actions.perform(.pasteSpecial(.formats)) }
            Button("Transpose") { actions.perform(.pasteSpecial(.transpose)) }
        }
        Divider()
        Menu("Insert") {
            Button("Rows Above") { actions.perform(.insertRows(below: false)) }
            Button("Rows Below") { actions.perform(.insertRows(below: true)) }
            Button("Columns Left") { actions.perform(.insertColumns(right: false)) }
            Button("Columns Right") { actions.perform(.insertColumns(right: true)) }
        }
        Menu("Delete") {
            Button("Rows") { actions.perform(.deleteRows) }
            Button("Columns") { actions.perform(.deleteColumns) }
        }
        Button("Clear Contents") { actions.perform(.clearContents) }
        Divider()
        Button("Sort A to Z") { actions.perform(.sort(ascending: true)) }
        Button("Sort Z to A") { actions.perform(.sort(ascending: false)) }
        Button("Filter by Selected Cell's Value") { actions.perform(.filterBySelection) }
        Divider()
        Button("Merge & Center") { actions.perform(.merge) }
        Button("Unmerge Cells") { actions.perform(.unmerge) }
        Button("Format Cells…") { actions.perform(.formatCells) }
    }
}
