import SheetCore
import SwiftUI

/// A titled group of inspector controls.
struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A square icon button for the inspector, highlighted when its setting is on.
struct InspectorIconButton: View {
    let title: String
    let systemImage: String
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .frame(width: 30, height: 26)
                .foregroundStyle(isOn ? WorkbookView.accent : Color.primary.opacity(0.75))
                .background(isOn ? WorkbookView.accent.opacity(0.14) : Color.primary.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// A full-width text button for the inspector.
struct InspectorButton: View {
    let title: String
    var systemImage: String?
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).frame(width: 16) }
                Text(title)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? Color.red : Color.primary)
    }
}

extension WorkbookView {
    var inspector: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: Binding(get: { model.inspector ?? .format }, set: { model.inspector = $0 })) {
                ForEach(InspectorPane.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if model.inspector == .organize {
                        organizePane
                    } else {
                        formatPane
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 290)
        .background(.background)
        .fileImporter(isPresented: $model.importingImage, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { insertImage(from: url) }
        }
    }

    // MARK: - Format

    @ViewBuilder
    private var formatPane: some View {
        let tabs = FormatTab.allCases.filter { $0 != .object || selectedObjectIndex != nil }
        Picker("Format", selection: Binding(get: { tabs.contains(model.formatTab) ? model.formatTab : .cell },
                                            set: { model.formatTab = $0 })) {
            ForEach(tabs) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        switch tabs.contains(model.formatTab) ? model.formatTab : .cell {
        case .cell: cellTab
        case .text: textTab
        case .table: tableTab
        case .object: objectTab
        }
    }

    @ViewBuilder
    private var cellTab: some View {
        InspectorSection(title: "Data Format") {
            Picker("Format", selection: Binding(
                get: { NumberFormatPreset.matching(activeFormat.numberFormat)?.rawValue ?? "Custom" },
                set: { name in
                    if let preset = NumberFormatPreset(rawValue: name) { setNumberFormat(preset.code) } else { showCustomFormat() }
                }
            )) {
                ForEach(NumberFormatPreset.allCases) { Text($0.rawValue).tag($0.rawValue) }
                Text("Custom…").tag("Custom")
            }
            .labelsHidden()
            HStack {
                Text(calculator.displayText(sheet: activeSheet, at: selection.active).isEmpty
                     ? (NumberFormatPreset.matching(activeFormat.numberFormat)?.example ?? "")
                     : calculator.displayText(sheet: activeSheet, at: selection.active))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                InspectorIconButton(title: "Fewer Decimals", systemImage: "minus") { stepDecimals(-1) }
                InspectorIconButton(title: "More Decimals", systemImage: "plus") { stepDecimals(1) }
            }
            InspectorButton(title: "Custom Format… (⌘1)", systemImage: "number") { showCustomFormat() }
        }
        InspectorSection(title: "Fill") {
            HStack(spacing: 8) {
                swatch(.fill, current: activeFormat.fillColor, title: "Fill Color")
                Text(activeFormat.fillColor.map { "#" + $0.hex } ?? "No fill").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
            }
        }
        InspectorSection(title: "Border") {
            HStack(spacing: 6) {
                InspectorIconButton(title: "No Border", systemImage: "square.dashed") { clearBorders() }
                InspectorIconButton(title: "All Borders", systemImage: "square.grid.3x3") {
                    applyBorders(.all(BorderLine(model.borderStyle)), all: true, "All Borders")
                }
                InspectorIconButton(title: "Outside Borders", systemImage: "square") {
                    applyBorders(.all(BorderLine(model.borderStyle)), "Outside Borders")
                }
                InspectorIconButton(title: "Top Border", systemImage: "rectangle.tophalf.inset.filled") {
                    applyBorders(CellBorder(top: BorderLine(model.borderStyle)), "Top Border")
                }
                InspectorIconButton(title: "Bottom Border", systemImage: "rectangle.bottomhalf.inset.filled") {
                    applyBorders(CellBorder(bottom: BorderLine(model.borderStyle)), "Bottom Border")
                }
            }
            Picker("Line", selection: $model.borderStyle) {
                Text("Thin").tag(BorderStyle.thin)
                Text("Medium").tag(BorderStyle.medium)
                Text("Thick").tag(BorderStyle.thick)
                Text("Dashed").tag(BorderStyle.dashed)
                Text("Dotted").tag(BorderStyle.dotted)
                Text("Double").tag(BorderStyle.double)
            }
        }
        InspectorSection(title: "Control") {
            Menu {
                Button("None") { applyControl(nil) }
                Button("Checkbox") { applyControl(.checkbox) }
                Button("Star Rating") { applyControl(.rating) }
                Button("Pop-Up Menu…") { startControl(.popUp) }
                Button("Stepper…") { startControl(.stepper) }
                Button("Slider…") { startControl(.slider) }
            } label: {
                Text(controlName(sheet.controls[selection.active]))
            }
        }
        InspectorSection(title: "Merge") {
            HStack {
                InspectorButton(title: "Merge & Center", systemImage: "rectangle.split.3x1") { mergeSelection(center: true, across: false) }
                InspectorButton(title: "Unmerge", systemImage: "rectangle.grid.1x2") { unmergeSelection() }
            }
        }
        InspectorSection(title: "Conditional Highlighting") {
            Menu { conditionalItems } label: { Text("Add a Rule") }
            Text("\(sheet.conditionalFormats.count) rule\(sheet.conditionalFormats.count == 1 ? "" : "s") on this sheet")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func controlName(_ control: CellControl?) -> String {
        switch control {
        case nil: "None"
        case .checkbox: "Checkbox"
        case .rating: "Star Rating"
        case .popUp: "Pop-Up Menu"
        case .stepper: "Stepper"
        case .slider: "Slider"
        }
    }

    @ViewBuilder
    private var textTab: some View {
        InspectorSection(title: "Font") {
            Menu {
                ForEach(Self.commonFonts, id: \.self) { name in Button(name) { setFontName(name) } }
                Divider()
                Menu("All Fonts") {
                    ForEach(Self.installedFonts, id: \.self) { name in Button(name) { setFontName(name) } }
                }
            } label: {
                Text(activeFontName)
            }
            HStack(spacing: 6) {
                Menu {
                    ForEach(Self.fontSizes, id: \.self) { size in Button(CellValue.number(size).displayText + " pt") { setFontSize(size) } }
                } label: {
                    Text(CellValue.number(activeFontSize).displayText + " pt")
                }
                .frame(width: 90)
                InspectorIconButton(title: "Smaller", systemImage: "textformat.size.smaller") { stepFontSize(up: false) }
                InspectorIconButton(title: "Larger", systemImage: "textformat.size.larger") { stepFontSize(up: true) }
                Spacer()
            }
            HStack(spacing: 6) {
                InspectorIconButton(title: "Bold (⌘B)", systemImage: "bold", isOn: activeFormat.bold) { toggle(\.bold, "Bold") }
                InspectorIconButton(title: "Italic (⌘I)", systemImage: "italic", isOn: activeFormat.italic) { toggle(\.italic, "Italic") }
                InspectorIconButton(title: "Underline (⌘U)", systemImage: "underline", isOn: activeFormat.underline) { toggle(\.underline, "Underline") }
                InspectorIconButton(title: "Strikethrough", systemImage: "strikethrough", isOn: activeFormat.strikethrough) {
                    toggle(\.strikethrough, "Strikethrough")
                }
                Spacer()
                swatch(.text, current: activeFormat.textColor, title: "Text Color")
            }
        }
        InspectorSection(title: "Alignment") {
            HStack(spacing: 6) {
                InspectorIconButton(title: "Align Left", systemImage: "text.alignleft", isOn: activeFormat.alignment == .left) {
                    updateFormats("Align Left") { $0.alignment = $0.alignment == .left ? .general : .left }
                }
                InspectorIconButton(title: "Center", systemImage: "text.aligncenter", isOn: activeFormat.alignment == .center) {
                    updateFormats("Center") { $0.alignment = $0.alignment == .center ? .general : .center }
                }
                InspectorIconButton(title: "Align Right", systemImage: "text.alignright", isOn: activeFormat.alignment == .right) {
                    updateFormats("Align Right") { $0.alignment = $0.alignment == .right ? .general : .right }
                }
                Spacer()
                InspectorIconButton(title: "Top", systemImage: "align.vertical.top", isOn: activeFormat.verticalAlignment == .top) {
                    updateFormats("Top Align") { $0.verticalAlignment = .top }
                }
                InspectorIconButton(title: "Middle", systemImage: "align.vertical.center", isOn: activeFormat.verticalAlignment == .center) {
                    updateFormats("Middle Align") { $0.verticalAlignment = .center }
                }
                InspectorIconButton(title: "Bottom", systemImage: "align.vertical.bottom", isOn: activeFormat.verticalAlignment == .bottom) {
                    updateFormats("Bottom Align") { $0.verticalAlignment = .bottom }
                }
            }
            HStack(spacing: 6) {
                Toggle("Wrap Text", isOn: Binding(get: { activeFormat.wrapText }, set: { _ in toggle(\.wrapText, "Wrap Text") }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                InspectorIconButton(title: "Decrease Indent", systemImage: "decrease.indent") { stepIndent(-1) }
                InspectorIconButton(title: "Increase Indent", systemImage: "increase.indent") { stepIndent(1) }
            }
        }
        InspectorSection(title: "Cell Style") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(CellStylePreset.allCases) { style in
                    let preview = style.apply(to: CellFormat())
                    Button { applyCellStyle(style) } label: {
                        Text(style.rawValue)
                            .font(.system(size: 11.5, weight: preview.bold ? .semibold : .regular))
                            .foregroundStyle(preview.textColor.map { Color($0) } ?? Color.black)
                            .frame(maxWidth: .infinity, minHeight: 26)
                            .background(preview.fillColor.map { Color($0) } ?? Color.white, in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var tableTab: some View {
        InspectorSection(title: "Table Style") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(TableStylePreset.allCases) { style in
                    Button { applyTableStyle(style) } label: { tableStyleSwatch(style) }
                        .buttonStyle(.plain)
                        .help(style.rawValue)
                }
            }
        }
        InspectorSection(title: "Rows & Columns") {
            HStack {
                InspectorButton(title: "Row Above", systemImage: "arrow.up.to.line.compact") { insertRows(below: false) }
                InspectorButton(title: "Row Below", systemImage: "arrow.down.to.line.compact") { insertRows(below: true) }
            }
            HStack {
                InspectorButton(title: "Column Left", systemImage: "arrow.left.to.line.compact") { insertColumns(right: false) }
                InspectorButton(title: "Column Right", systemImage: "arrow.right.to.line.compact") { insertColumns(right: true) }
            }
            HStack {
                InspectorButton(title: "Delete Rows", systemImage: "minus.rectangle", role: .destructive) { deleteRows() }
                InspectorButton(title: "Delete Columns", systemImage: "minus.rectangle", role: .destructive) { deleteColumns() }
            }
        }
        InspectorSection(title: "Headers") {
            Stepper("Frozen rows: \(sheet.frozenRows)", value: Binding(get: { sheet.frozenRows }, set: { setFrozenRows($0) }), in: 0...20)
                .font(.system(size: 12.5))
            Toggle("Gridlines", isOn: Binding(get: { sheet.showGridlines }, set: { _ in toggleGridlines() }))
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        InspectorSection(title: "Size & Visibility") {
            HStack {
                InspectorButton(title: "Fit Columns", systemImage: "arrow.left.and.right") { autofitColumns() }
                InspectorButton(title: "Fit Rows", systemImage: "arrow.up.and.down") { autofitRows() }
            }
            HStack {
                InspectorButton(title: "Hide Rows", systemImage: "eye.slash") { hideRows() }
                InspectorButton(title: "Hide Columns", systemImage: "eye.slash") { hideColumns() }
            }
            InspectorButton(title: "Show All Hidden Rows & Columns", systemImage: "eye") {
                unhideAllRows()
                unhideAllColumns()
            }
        }
    }

    private func tableStyleSwatch(_ style: TableStylePreset) -> some View {
        let colors = style.colors
        return VStack(spacing: 0) {
            Rectangle().fill(Color(SheetCore.RGBColor(hex: colors.header)!)).frame(height: 9)
            ForEach(0..<3, id: \.self) { row in
                Rectangle().fill(row % 2 == 1 ? Color(SheetCore.RGBColor(hex: colors.band)!) : Color.white).frame(height: 7)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.12)))
        .frame(height: 30)
    }

    @ViewBuilder
    private var objectTab: some View {
        if let objectIndex = selectedObjectIndex {
            let object = sheet.canvas[objectIndex]
            InspectorSection(title: "Arrange") {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        numberField("X", object.x) { value in updateSelectedObject("Move Object") { $0.x = max(0, value) } }
                        numberField("Y", object.y) { value in updateSelectedObject("Move Object") { $0.y = max(0, value) } }
                    }
                    GridRow {
                        numberField("W", object.width) { value in updateSelectedObject("Resize Object") { $0.width = max(24, value) } }
                        numberField("H", object.height) { value in updateSelectedObject("Resize Object") { $0.height = max(24, value) } }
                    }
                }
                HStack {
                    InspectorButton(title: "Front", systemImage: "square.3.layers.3d.top.filled") { reorderSelectedObject(toFront: true) }
                    InspectorButton(title: "Back", systemImage: "square.3.layers.3d.bottom.filled") { reorderSelectedObject(toFront: false) }
                }
            }
            switch object.kind {
            case .chart(let kind, let range, let title):
                InspectorSection(title: "Chart") {
                    Picker("Type", selection: Binding(get: { kind }, set: { newKind in
                        updateSelectedObject("Chart Type") { $0.kind = .chart(newKind, range: range, title: title) }
                    })) {
                        Text("Column").tag(CanvasObject.ChartKind.column)
                        Text("Bar").tag(CanvasObject.ChartKind.bar)
                        Text("Line").tag(CanvasObject.ChartKind.line)
                        Text("Pie").tag(CanvasObject.ChartKind.pie)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    TextField("Title", text: Binding(get: { title }, set: { newTitle in
                        updateSelectedObject("Chart Title") { $0.kind = .chart(kind, range: range, title: newTitle) }
                    }))
                    .textFieldStyle(.roundedBorder)
                    HStack {
                        Text("Data: \(range.a1)").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Use Selection") {
                            let selected = selection.range
                            updateSelectedObject("Chart Data") { $0.kind = .chart(kind, range: selected, title: title) }
                        }
                        .disabled(selection.range.cellCount < 2)
                    }
                }
            case .text:
                InspectorSection(title: "Text") {
                    HStack(spacing: 6) {
                        Stepper("\(Int(object.fontSize)) pt", value: Binding(get: { object.fontSize },
                                                                            set: { size in updateSelectedObject("Text Size") { $0.fontSize = size } }),
                                in: 8...96)
                            .font(.system(size: 12.5))
                        Spacer()
                        InspectorIconButton(title: "Bold", systemImage: "bold", isOn: object.bold) {
                            updateSelectedObject("Bold") { $0.bold.toggle() }
                        }
                        swatch(.objectText, current: object.textColor, title: "Text Color")
                    }
                    InspectorButton(title: "Edit Text", systemImage: "character.cursor.ibeam") { model.editingObject = object.id }
                }
                objectColors(object)
            case .shape:
                objectColors(object)
            case .image:
                InspectorSection(title: "Border") {
                    HStack(spacing: 8) {
                        swatch(.objectStroke, current: object.stroke, title: "Border Color")
                        Text(object.stroke == nil ? "No border" : "Border").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
            InspectorButton(title: "Delete", systemImage: "trash", role: .destructive) { deleteSelectedObject() }
        }
    }

    private func objectColors(_ object: CanvasObject) -> some View {
        InspectorSection(title: "Fill & Line") {
            HStack(spacing: 10) {
                swatch(.objectFill, current: object.fill, title: "Fill Color")
                Text("Fill").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                swatch(.objectStroke, current: object.stroke, title: "Line Color")
                Text("Line").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private func numberField(_ label: String, _ value: Double, onCommit: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).frame(width: 14)
            TextField(label, value: Binding(get: { value.rounded() }, set: onCommit), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 84)
        }
    }

    /// A color well that opens the palette.
    func swatch(_ target: PaletteTarget, current: SheetCore.RGBColor?, title: String) -> some View {
        Button { model.palette = target } label: {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(current.map { Color($0) } ?? Color.white)
                .overlay {
                    if current == nil {
                        Path { path in
                            path.move(to: CGPoint(x: 4, y: 20))
                            path.addLine(to: CGPoint(x: 24, y: 4))
                        }
                        .stroke(Color.red.opacity(0.7), lineWidth: 1.5)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.black.opacity(0.15)))
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .popover(isPresented: Binding(get: { model.palette == target }, set: { if !$0 { model.palette = nil } })) {
            ColorPalette(title: title, noneTitle: target == .text || target == .objectText ? "Automatic" : "None") { color in
                model.palette = nil
                switch target {
                case .fill: updateFormats(title) { $0.fillColor = color }
                case .text: updateFormats(title) { $0.textColor = color }
                case .objectFill: updateSelectedObject(title) { $0.fill = color }
                case .objectStroke: updateSelectedObject(title) { $0.stroke = color }
                case .objectText: updateSelectedObject(title) { $0.textColor = color }
                }
            }
        }
    }

    @ViewBuilder
    var conditionalItems: some View {
        Menu("Highlight Cells") {
            Button("Greater Than…") { startRule(.greaterThan) }
            Button("Less Than…") { startRule(.lessThan) }
            Button("Between…") { startRule(.between) }
            Button("Equal To…") { startRule(.equalTo) }
            Button("Text That Contains…") { startRule(.textContains) }
            Button("Duplicate Values") { addDuplicateRule(unique: false) }
            Button("Unique Values") { addDuplicateRule(unique: true) }
        }
        Menu("Top & Bottom") {
            Button("Top 10 Items…") { startRule(.top) }
            Button("Top 10%…") { startRule(.topPercent) }
            Button("Bottom 10 Items…") { startRule(.bottom) }
            Button("Bottom 10%…") { startRule(.bottomPercent) }
            Button("Above Average") { addAverageRule(below: false) }
            Button("Below Average") { addAverageRule(below: true) }
        }
        Menu("Data Bars") {
            Button("Green") { addDataBar("63C384") }
            Button("Blue") { addDataBar("638EC6") }
            Button("Orange") { addDataBar("FFB628") }
            Button("Red") { addDataBar("FF555A") }
            Button("Purple") { addDataBar("D6007B") }
        }
        Menu("Color Scales") {
            Button("Green – Yellow – Red") { addColorScale(["F8696B", "FFEB84", "63BE7B"].reversed()) }
            Button("Red – Yellow – Green") { addColorScale(["F8696B", "FFEB84", "63BE7B"]) }
            Button("Blue – White – Red") { addColorScale(["F8696B", "FCFCFF", "5A8AC6"].reversed()) }
            Button("White – Green") { addColorScale(["FCFCFF", "63BE7B"]) }
        }
        Button("Rule with a Formula…") { startRule(.formula) }
    }

    // MARK: - Organize

    @ViewBuilder
    private var organizePane: some View {
        Picker("Organize", selection: $model.organizeTab) {
            ForEach(OrganizeTab.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        switch model.organizeTab {
        case .sort: sortTab
        case .highlight: highlightTab
        }
    }

    @ViewBuilder
    private var sortTab: some View {
        let column = CellAddress.columnName(selection.active.column)
        InspectorSection(title: "Sort") {
            Text("Sorts the table around the selection by column \(column).")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                InspectorButton(title: "Ascending", systemImage: "arrow.up") { sortSelection(ascending: true) }
                InspectorButton(title: "Descending", systemImage: "arrow.down") { sortSelection(ascending: false) }
            }
        }
        InspectorSection(title: "Filter") {
            Toggle("Filter rows with header menus", isOn: Binding(get: { sheet.filter != nil }, set: { _ in toggleFilter() }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 12.5))
            if let filter = sheet.filter {
                Text("\(filter.allowedValues.count) column\(filter.allowedValues.count == 1 ? "" : "s") filtered in \(filter.range.a1)")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                InspectorButton(title: "Show All Rows", systemImage: "line.3.horizontal.decrease") { clearFilterCriteria() }
                InspectorButton(title: "Show Only \"\(calculator.displayText(sheet: activeSheet, at: selection.active))\"",
                                systemImage: "scope") { filterBySelectedValue() }
            }
        }
        InspectorSection(title: "Categories") {
            Text("Groups the table by column \(column) on a new sheet with counts, totals and averages that stay up to date.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            InspectorButton(title: "Summarize by Category", systemImage: "rectangle.3.group") { summarizeByCategory() }
        }
        InspectorSection(title: "Clean Up") {
            InspectorButton(title: "Remove Duplicate Rows", systemImage: "square.on.square.dashed") { removeDuplicates() }
            InspectorButton(title: "Find & Replace (⌘F)", systemImage: "magnifyingglass") { showFind() }
        }
    }

    @ViewBuilder
    private var highlightTab: some View {
        InspectorSection(title: "Rules on This Sheet") {
            if sheet.conditionalFormats.isEmpty {
                Text("No highlighting rules yet. Select cells and add one below.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(sheet.conditionalFormats.indices, id: \.self) { index in
                let rule = sheet.conditionalFormats[index]
                HStack(alignment: .top, spacing: 8) {
                    ruleSwatch(rule.rule)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.describe(rule.rule)).font(.system(size: 12))
                        Text(rule.ranges.map(\.a1).joined(separator: ", ")).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        let sheetIndex = activeSheet
                        mutate("Delete Rule") { $0.sheets[sheetIndex].conditionalFormats.remove(at: index) }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Delete Rule")
                }
                .padding(8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        InspectorSection(title: "Add a Rule") {
            Menu { conditionalItems } label: { Text("Choose a Rule") }
            InspectorButton(title: "Clear Rules from Selection", systemImage: "eraser") { clearRules(sheetWide: false) }
        }
    }

    private func ruleSwatch(_ rule: ConditionalRule) -> some View {
        let fill: Color
        switch rule {
        case .colorScale(let stops): fill = stops.last.map { Color($0.color) } ?? .gray
        case .dataBar(let color): fill = Color(color)
        default: fill = rule.style?.fillColor.map { Color($0) } ?? Color.white
        }
        return RoundedRectangle(cornerRadius: 3).fill(fill)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.15)))
            .frame(width: 16, height: 16)
    }

    static func describe(_ rule: ConditionalRule) -> String {
        func clean(_ formula: String) -> String { formula.replacingOccurrences(of: "\"", with: "") }
        switch rule {
        case .cellIs(let op, let first, let second, _):
            switch op {
            case .greaterThan: return "Greater than \(clean(first))"
            case .lessThan: return "Less than \(clean(first))"
            case .greaterThanOrEqual: return "At least \(clean(first))"
            case .lessThanOrEqual: return "At most \(clean(first))"
            case .equal: return "Equal to \(clean(first))"
            case .notEqual: return "Not equal to \(clean(first))"
            case .between: return "Between \(clean(first)) and \(clean(second ?? ""))"
            case .notBetween: return "Not between \(clean(first)) and \(clean(second ?? ""))"
            }
        case .text(let match, let text, _):
            switch match {
            case .containsText: return "Text contains “\(text)”"
            case .notContainsText: return "Text does not contain “\(text)”"
            case .beginsWith: return "Text begins with “\(text)”"
            case .endsWith: return "Text ends with “\(text)”"
            }
        case .duplicates(let unique, _): return unique ? "Unique values" : "Duplicate values"
        case .top(let rank, let bottom, let percent, _): return "\(bottom ? "Bottom" : "Top") \(rank)\(percent ? "%" : "")"
        case .average(let below, _): return below ? "Below average" : "Above average"
        case .expression(let formula, _): return "Formula: =\(formula)"
        case .colorScale(let stops): return "\(stops.count)-color scale"
        case .dataBar: return "Data bars"
        }
    }
}
