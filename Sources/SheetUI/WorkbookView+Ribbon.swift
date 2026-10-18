import SheetCore
import SwiftUI

/// A titled block of ribbon controls, separated from the next by a divider.
struct RibbonGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 3) {
                HStack(alignment: .center, spacing: 3) { content }
                    .frame(minHeight: 48)
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            Divider().frame(height: 60)
        }
    }
}

/// Icon, optionally with a caption below it for the large ribbon buttons.
struct RibbonLabel: View {
    let title: String
    var systemImage: String?
    var glyph: String?
    var large = false
    var isOn = false

    var body: some View {
        Group {
            if large {
                VStack(spacing: 2) {
                    icon.font(.system(size: 18))
                    Text(title).font(.system(size: 10)).lineLimit(1)
                }
                .frame(minWidth: 50, minHeight: 46)
            } else {
                icon.font(.system(size: 13))
                    .frame(minWidth: 26, minHeight: 22)
            }
        }
        .padding(.horizontal, 2)
        .background(isOn ? Color.accentColor.opacity(0.22) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var icon: some View {
        if let systemImage {
            Image(systemName: systemImage)
        } else {
            Text(glyph ?? title).font(.system(size: large ? 15 : 12, weight: .semibold)).lineLimit(1)
        }
    }
}

struct RibbonButton: View {
    let title: String
    var systemImage: String?
    var glyph: String?
    var large = false
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RibbonLabel(title: title, systemImage: systemImage, glyph: glyph, large: large, isOn: isOn)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

struct RibbonMenu<Content: View>: View {
    let title: String
    var systemImage: String?
    var glyph: String?
    var large = false
    @ViewBuilder let content: Content

    var body: some View {
        Menu {
            content
        } label: {
            RibbonLabel(title: title, systemImage: systemImage, glyph: glyph, large: large)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(title)
        .accessibilityLabel(title)
    }
}

extension WorkbookView {
    var ribbon: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(RibbonTab.allCases) { tab in
                    Button { model.ribbonTab = tab } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: model.ribbonTab == tab ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                model.ribbonTab == tab ? Color.accentColor.opacity(0.15) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    switch model.ribbonTab {
                    case .home: homeTab
                    case .insert: insertTab
                    case .formulas: formulasTab
                    case .data: dataTab
                    case .view: viewTab
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
        }
        .background(Color.gray.opacity(0.06))
    }

    // MARK: - Home

    @ViewBuilder
    private var homeTab: some View {
        RibbonGroup(title: "Clipboard") {
            RibbonButton(title: "Paste", systemImage: "doc.on.clipboard", large: true) { pasteFromSystem() }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 2) {
                    RibbonButton(title: "Cut", systemImage: "scissors") { _ = cutSelection() }
                    RibbonButton(title: "Copy", systemImage: "doc.on.doc") { _ = copySelection() }
                }
                HStack(spacing: 2) {
                    RibbonButton(title: "Format Painter", systemImage: "paintbrush.pointed", isOn: model.painter != nil) {
                        model.painter = model.painter == nil ? activeFormat : nil
                    }
                    RibbonMenu(title: "Paste Special", systemImage: "list.clipboard") { pasteSpecialItems }
                }
            }
            VStack(spacing: 2) {
                RibbonButton(title: "Undo", systemImage: "arrow.uturn.backward") { undoManager?.undo() }
                RibbonButton(title: "Redo", systemImage: "arrow.uturn.forward") { undoManager?.redo() }
            }
        }
        RibbonGroup(title: "Font") {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 2) {
                    RibbonMenu(title: "Font", glyph: String(activeFontName.prefix(14)) + " ▾") {
                        ForEach(Self.commonFonts, id: \.self) { name in
                            Button(name) { setFontName(name) }
                        }
                        Divider()
                        Menu("All Fonts") {
                            ForEach(Self.installedFonts, id: \.self) { name in
                                Button(name) { setFontName(name) }
                            }
                        }
                    }
                    RibbonMenu(title: "Font Size", glyph: CellValue.number(activeFontSize).displayText + " ▾") {
                        ForEach(Self.fontSizes, id: \.self) { size in
                            Button(CellValue.number(size).displayText) { setFontSize(size) }
                        }
                    }
                    RibbonButton(title: "Increase Font Size", glyph: "A↑") { stepFontSize(up: true) }
                    RibbonButton(title: "Decrease Font Size", glyph: "A↓") { stepFontSize(up: false) }
                }
                HStack(spacing: 2) {
                    RibbonButton(title: "Bold (⌘B)", systemImage: "bold", isOn: activeFormat.bold) { toggle(\.bold, "Bold") }
                    RibbonButton(title: "Italic (⌘I)", systemImage: "italic", isOn: activeFormat.italic) { toggle(\.italic, "Italic") }
                    RibbonButton(title: "Underline (⌘U)", systemImage: "underline", isOn: activeFormat.underline) { toggle(\.underline, "Underline") }
                    RibbonButton(title: "Strikethrough", systemImage: "strikethrough", isOn: activeFormat.strikethrough) { toggle(\.strikethrough, "Strikethrough") }
                    bordersMenu
                    paletteButton(.fill, title: "Fill Color", systemImage: "paintbrush.fill", current: activeFormat.fillColor)
                    paletteButton(.text, title: "Font Color", systemImage: "character", current: activeFormat.textColor)
                }
            }
        }
        RibbonGroup(title: "Alignment") {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 2) {
                    RibbonButton(title: "Top Align", systemImage: "align.vertical.top", isOn: activeFormat.verticalAlignment == .top) {
                        updateFormats("Top Align") { $0.verticalAlignment = .top }
                    }
                    RibbonButton(title: "Middle Align", systemImage: "align.vertical.center", isOn: activeFormat.verticalAlignment == .center) {
                        updateFormats("Middle Align") { $0.verticalAlignment = .center }
                    }
                    RibbonButton(title: "Bottom Align", systemImage: "align.vertical.bottom", isOn: activeFormat.verticalAlignment == .bottom) {
                        updateFormats("Bottom Align") { $0.verticalAlignment = .bottom }
                    }
                    RibbonButton(title: "Wrap Text", systemImage: "text.word.spacing", isOn: activeFormat.wrapText) {
                        toggle(\.wrapText, "Wrap Text")
                    }
                }
                HStack(spacing: 2) {
                    RibbonButton(title: "Align Left", systemImage: "text.alignleft", isOn: activeFormat.alignment == .left) {
                        updateFormats("Align Left") { $0.alignment = $0.alignment == .left ? .general : .left }
                    }
                    RibbonButton(title: "Center", systemImage: "text.aligncenter", isOn: activeFormat.alignment == .center) {
                        updateFormats("Center") { $0.alignment = $0.alignment == .center ? .general : .center }
                    }
                    RibbonButton(title: "Align Right", systemImage: "text.alignright", isOn: activeFormat.alignment == .right) {
                        updateFormats("Align Right") { $0.alignment = $0.alignment == .right ? .general : .right }
                    }
                    RibbonButton(title: "Decrease Indent", systemImage: "decrease.indent") { stepIndent(-1) }
                    RibbonButton(title: "Increase Indent", systemImage: "increase.indent") { stepIndent(1) }
                }
            }
            RibbonMenu(title: "Merge", systemImage: "rectangle.split.3x1", large: true) {
                Button("Merge & Center") { mergeSelection(center: true, across: false) }
                Button("Merge Across") { mergeSelection(center: false, across: true) }
                Button("Merge Cells") { mergeSelection(center: false, across: false) }
                Button("Unmerge Cells") { unmergeSelection() }
            }
        }
        RibbonGroup(title: "Number") {
            VStack(alignment: .leading, spacing: 2) {
                RibbonMenu(title: "Number Format", glyph: (NumberFormatPreset.matching(activeFormat.numberFormat)?.rawValue ?? "Custom") + " ▾") {
                    ForEach(NumberFormatPreset.allCases) { preset in
                        Button("\(preset.rawValue)    \(preset.example)") { setNumberFormat(preset.code) }
                    }
                    Divider()
                    Button("More Number Formats… (⌘1)") { showCustomFormat() }
                }
                HStack(spacing: 2) {
                    RibbonButton(title: "Accounting (⌃⇧4 for Currency)", glyph: "$") { setNumberFormat(NumberFormatPreset.accounting.code) }
                    RibbonButton(title: "Percent (⌃⇧5)", glyph: "%") { setNumberFormat("0%") }
                    RibbonButton(title: "Comma Style", glyph: ",") { setNumberFormat("#,##0.00") }
                    RibbonButton(title: "Increase Decimal", glyph: ".0+") { stepDecimals(1) }
                    RibbonButton(title: "Decrease Decimal", glyph: ".0−") { stepDecimals(-1) }
                }
            }
        }
        RibbonGroup(title: "Styles") {
            conditionalFormattingMenu
            RibbonMenu(title: "Cell Styles", systemImage: "paintpalette", large: true) {
                ForEach(CellStylePreset.allCases) { style in
                    Button(style.rawValue) { applyCellStyle(style) }
                }
            }
        }
        RibbonGroup(title: "Cells") {
            RibbonMenu(title: "Insert", systemImage: "plus.rectangle.on.rectangle", large: true) {
                Button("Insert Rows Above") { insertRows(below: false) }
                Button("Insert Rows Below") { insertRows(below: true) }
                Button("Insert Columns Left") { insertColumns(right: false) }
                Button("Insert Columns Right") { insertColumns(right: true) }
                Button("Insert Sheet") { addSheet() }
            }
            RibbonMenu(title: "Delete", systemImage: "minus.rectangle", large: true) {
                Button("Delete Rows") { deleteRows() }
                Button("Delete Columns") { deleteColumns() }
                Button("Delete Sheet") { deleteSheet(activeSheet) }.disabled(workbook.sheets.count < 2)
            }
            RibbonMenu(title: "Format", systemImage: "rectangle.3.group", large: true) {
                Button("AutoFit Row Height") { autofitRows() }
                Button("AutoFit Column Width") { autofitColumns() }
                Button("Reset Column Width") { resetColumnWidths() }
                Divider()
                Button("Hide Rows") { hideRows() }
                Button("Unhide Rows") { unhideRows() }
                Button("Unhide All Rows") { unhideAllRows() }
                Button("Hide Columns") { hideColumns() }
                Button("Unhide Columns") { unhideColumns() }
                Button("Unhide All Columns") { unhideAllColumns() }
                Divider()
                Button("Rename Sheet…") { startRename(activeSheet) }
                Button("Format Cells… (⌘1)") { showCustomFormat() }
            }
        }
        RibbonGroup(title: "Editing") {
            autoSumMenu(large: true)
            VStack(alignment: .leading, spacing: 2) {
                RibbonButton(title: "Fill Down (⌘D)", systemImage: "arrow.down.to.line") { fillDown() }
                RibbonMenu(title: "Clear", systemImage: "eraser") {
                    Button("Clear All") { clearAll() }
                    Button("Clear Formats") { clearFormats() }
                    Button("Clear Contents") { clearSelection() }
                }
            }
            RibbonMenu(title: "Sort & Filter", systemImage: "arrow.up.arrow.down", large: true) {
                Button("Sort A to Z") { sortSelection(ascending: true) }
                Button("Sort Z to A") { sortSelection(ascending: false) }
                Divider()
                Button(sheet.filter == nil ? "Filter" : "Remove Filter") { toggleFilter() }
                Button("Clear Filter Criteria") { clearFilterCriteria() }.disabled(sheet.filter?.allowedValues.isEmpty ?? true)
            }
            RibbonButton(title: "Find & Replace (⌘F)", systemImage: "magnifyingglass", large: true) { showFind() }
        }
    }

    private var conditionalFormattingMenu: some View {
        RibbonMenu(title: "Conditional", systemImage: "square.grid.3x3.topleft.filled", large: true) {
            Menu("Highlight Cells Rules") {
                Button("Greater Than…") { startRule(.greaterThan) }
                Button("Less Than…") { startRule(.lessThan) }
                Button("Between…") { startRule(.between) }
                Button("Equal To…") { startRule(.equalTo) }
                Button("Text That Contains…") { startRule(.textContains) }
                Button("Duplicate Values") { addDuplicateRule(unique: false) }
                Button("Unique Values") { addDuplicateRule(unique: true) }
            }
            Menu("Top/Bottom Rules") {
                Button("Top 10 Items…") { startRule(.top) }
                Button("Top 10%…") { startRule(.topPercent) }
                Button("Bottom 10 Items…") { startRule(.bottom) }
                Button("Bottom 10%…") { startRule(.bottomPercent) }
                Button("Above Average") { addAverageRule(below: false) }
                Button("Below Average") { addAverageRule(below: true) }
            }
            Menu("Data Bars") {
                Button("Blue") { addDataBar("638EC6") }
                Button("Green") { addDataBar("63C384") }
                Button("Red") { addDataBar("FF555A") }
                Button("Orange") { addDataBar("FFB628") }
                Button("Light Blue") { addDataBar("008AEF") }
                Button("Purple") { addDataBar("D6007B") }
            }
            Menu("Color Scales") {
                Button("Green – Yellow – Red") { addColorScale(["F8696B", "FFEB84", "63BE7B"].reversed()) }
                Button("Red – Yellow – Green") { addColorScale(["F8696B", "FFEB84", "63BE7B"]) }
                Button("Green – White – Red") { addColorScale(["F8696B", "FCFCFF", "63BE7B"].reversed()) }
                Button("Blue – White – Red") { addColorScale(["F8696B", "FCFCFF", "5A8AC6"].reversed()) }
                Button("White – Red") { addColorScale(["FCFCFF", "F8696B"]) }
                Button("White – Green") { addColorScale(["FCFCFF", "63BE7B"]) }
            }
            Divider()
            Button("New Rule with a Formula…") { startRule(.formula) }
            Menu("Clear Rules") {
                Button("Clear Rules from Selected Cells") { clearRules(sheetWide: false) }
                Button("Clear Rules from Entire Sheet") { clearRules(sheetWide: true) }
            }
        }
    }

    private var bordersMenu: some View {
        RibbonMenu(title: "Borders", systemImage: "square.dashed") {
            Button("Bottom Border") { applyBorders(CellBorder(bottom: BorderLine()), "Bottom Border") }
            Button("Top Border") { applyBorders(CellBorder(top: BorderLine()), "Top Border") }
            Button("Left Border") { applyBorders(CellBorder(left: BorderLine()), "Left Border") }
            Button("Right Border") { applyBorders(CellBorder(right: BorderLine()), "Right Border") }
            Divider()
            Button("No Border") { clearBorders() }
            Button("All Borders") { applyBorders(.all(BorderLine()), all: true, "All Borders") }
            Button("Outside Borders") { applyBorders(.all(BorderLine()), "Outside Borders") }
            Button("Thick Outside Borders") { applyBorders(.all(BorderLine(.thick)), "Thick Outside Borders") }
            Divider()
            Button("Bottom Double Border") { applyBorders(CellBorder(bottom: BorderLine(.double)), "Bottom Double Border") }
            Button("Thick Bottom Border") { applyBorders(CellBorder(bottom: BorderLine(.thick)), "Thick Bottom Border") }
            Button("Top and Bottom Border") { applyBorders(CellBorder(top: BorderLine(), bottom: BorderLine()), "Top and Bottom Border") }
            Button("Top and Double Bottom Border") {
                applyBorders(CellBorder(top: BorderLine(), bottom: BorderLine(.double)), "Top and Double Bottom Border")
            }
            Button("Dashed Outside Borders") { applyBorders(.all(BorderLine(.dashed)), "Dashed Outside Borders") }
        }
    }

    private func paletteButton(_ target: PaletteTarget, title: String, systemImage: String, current: SheetCore.RGBColor?) -> some View {
        Button { model.palette = target } label: {
            VStack(spacing: 1) {
                Image(systemName: systemImage).font(.system(size: 12))
                Rectangle()
                    .fill(current.map { Color($0) } ?? (target == .fill ? Color.clear : Color.primary))
                    .frame(width: 16, height: 3)
                    .overlay(Rectangle().stroke(Color.gray.opacity(0.4), lineWidth: 0.5))
            }
            .frame(minWidth: 26, minHeight: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .popover(isPresented: Binding(get: { model.palette == target }, set: { if !$0 { model.palette = nil } })) {
            ColorPalette(title: title, noneTitle: target == .fill ? "No Fill" : "Automatic") { color in
                model.palette = nil
                updateFormats(title) {
                    if target == .fill { $0.fillColor = color } else { $0.textColor = color }
                }
            }
        }
    }

    private func autoSumMenu(large: Bool) -> some View {
        RibbonMenu(title: "AutoSum", glyph: "Σ", large: large) {
            Button("Sum") { autoSum("SUM") }
            Button("Average") { autoSum("AVERAGE") }
            Button("Count Numbers") { autoSum("COUNT") }
            Button("Max") { autoSum("MAX") }
            Button("Min") { autoSum("MIN") }
        }
    }

    // MARK: - Insert

    @ViewBuilder
    private var insertTab: some View {
        RibbonGroup(title: "Cells") {
            RibbonButton(title: "Rows Above", systemImage: "arrow.up.to.line.compact", large: true) { insertRows(below: false) }
            RibbonButton(title: "Columns Left", systemImage: "arrow.left.to.line.compact", large: true) { insertColumns(right: false) }
            RibbonButton(title: "New Sheet", systemImage: "doc.badge.plus", large: true) { addSheet() }
        }
        RibbonGroup(title: "Charts") {
            RibbonButton(title: "Column", systemImage: "chart.bar.fill", large: true) { insertChart(.column) }
            RibbonButton(title: "Bar", systemImage: "chart.bar.xaxis", large: true) { insertChart(.bar) }
            RibbonButton(title: "Line", systemImage: "chart.xyaxis.line", large: true) { insertChart(.line) }
            RibbonButton(title: "Pie", systemImage: "chart.pie.fill", large: true) { insertChart(.pie) }
        }
        RibbonGroup(title: "Date & Time") {
            RibbonButton(title: "Today (⌘;)", systemImage: "calendar", large: true) { insertNow(time: false) }
            RibbonButton(title: "Now (⇧⌘;)", systemImage: "clock", large: true) { insertNow(time: true) }
        }
        RibbonGroup(title: "Functions") {
            functionMenus
        }
    }

    // MARK: - Formulas

    @ViewBuilder
    private var formulasTab: some View {
        RibbonGroup(title: "Function Library") {
            autoSumMenu(large: true)
            functionMenus
        }
        RibbonGroup(title: "Defined Names") {
            RibbonMenu(title: "Names", systemImage: "tag", large: true) {
                if workbook.definedNames.isEmpty {
                    Text("No names in this workbook")
                } else {
                    ForEach(workbook.definedNames.indices, id: \.self) { index in
                        let name = workbook.definedNames[index]
                        Button("\(name.name)  =\(name.formula)") { insertFunctionName(name.name) }
                    }
                }
            }
        }
        RibbonGroup(title: "Formula Auditing") {
            RibbonButton(title: "Show Formulas", systemImage: "function", large: true, isOn: model.showFormulas) {
                model.showFormulas.toggle()
            }
        }
    }

    /// Types a defined name into the formula being edited, or starts a formula with it.
    private func insertFunctionName(_ name: String) {
        if var current = editor {
            current.text += (current.text.isEmpty ? "=" : "") + name
            editor = current
            focusEditor(current)
        } else {
            beginEditing(at: selection.active, text: "=" + name)
        }
    }

    @ViewBuilder
    private var functionMenus: some View {
        ForEach(FunctionCategory.allCases, id: \.self) { category in
            RibbonMenu(title: category.rawValue, systemImage: Self.symbol(for: category), large: true) {
                ForEach(FunctionCatalog.all.filter { $0.category == category }) { info in
                    Button(info.name + " — " + info.summary) { insertFunction(info.name) }
                }
            }
        }
    }

    private static func symbol(for category: FunctionCategory) -> String {
        switch category {
        case .math: "plus.forwardslash.minus"
        case .statistical: "chart.bar.xaxis"
        case .logical: "questionmark.diamond"
        case .text: "textformat"
        case .lookup: "magnifyingglass"
        case .dateTime: "calendar"
        case .financial: "dollarsign.circle"
        case .information: "info.circle"
        }
    }

    // MARK: - Data

    @ViewBuilder
    private var dataTab: some View {
        RibbonGroup(title: "Sort & Filter") {
            RibbonButton(title: "Sort A to Z", systemImage: "arrow.up", large: true) { sortSelection(ascending: true) }
            RibbonButton(title: "Sort Z to A", systemImage: "arrow.down", large: true) { sortSelection(ascending: false) }
            RibbonButton(title: "Filter (⌘⇧L)", systemImage: "line.3.horizontal.decrease.circle", large: true, isOn: sheet.filter != nil) {
                toggleFilter()
            }
            RibbonButton(title: "Clear", systemImage: "xmark.circle", large: true) { clearFilterCriteria() }
        }
        RibbonGroup(title: "Data Tools") {
            RibbonButton(title: "Remove Duplicates", systemImage: "square.on.square.dashed", large: true) { removeDuplicates() }
            RibbonButton(title: "Find & Replace", systemImage: "magnifyingglass", large: true) { showFind() }
        }
    }

    // MARK: - View

    @ViewBuilder
    private var viewTab: some View {
        RibbonGroup(title: "Show") {
            RibbonButton(title: "Gridlines", systemImage: "grid", large: true, isOn: sheet.showGridlines) { toggleGridlines() }
            RibbonButton(title: "Formulas", systemImage: "function", large: true, isOn: model.showFormulas) { model.showFormulas.toggle() }
        }
        RibbonGroup(title: "Zoom") {
            RibbonButton(title: "Zoom Out (⌘−)", systemImage: "minus.magnifyingglass", large: true) { setZoom(model.zoom - 0.1) }
            RibbonButton(title: "100%", glyph: "100%", large: true) { setZoom(1) }
            RibbonButton(title: "Zoom In (⌘=)", systemImage: "plus.magnifyingglass", large: true) { setZoom(model.zoom + 0.1) }
        }
        RibbonGroup(title: "Window") {
            RibbonButton(title: "Freeze Top Row", systemImage: "rectangle.tophalf.inset.filled", large: true, isOn: sheet.frozenRows == 1) {
                setFrozenRows(sheet.frozenRows == 1 ? 0 : 1)
            }
            RibbonButton(title: "Freeze Above Selection", systemImage: "rectangle.split.1x2", large: true) {
                setFrozenRows(selection.active.row)
            }
            RibbonButton(title: "Unfreeze", systemImage: "rectangle", large: true) { setFrozenRows(0) }
        }
    }
}
