import CoreTransferable
import SheetCore
import SwiftUI
import UniformTypeIdentifiers

/// An icon with a short caption, the building block of the toolbar.
struct ToolLabel: View {
    let title: String
    let systemImage: String
    var isOn = false

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .regular))
                .frame(height: 19)
            Text(title)
                .font(.system(size: 10.5))
                .lineLimit(1)
        }
        .foregroundStyle(isOn ? WorkbookView.accent : Color.primary.opacity(0.78))
        .frame(minWidth: 50)
        .padding(.horizontal, 4)
        .padding(.vertical, 5)
        .background(isOn ? WorkbookView.accent.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
    }
}

struct ToolButton: View {
    let title: String
    let systemImage: String
    var isOn = false
    var help: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) { ToolLabel(title: title, systemImage: systemImage, isOn: isOn) }
            .buttonStyle(.plain)
            .help(help ?? title)
    }
}

struct ToolMenu<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        Menu { content } label: { ToolLabel(title: title, systemImage: systemImage) }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(title)
    }
}

/// The workbook as an .xlsx file for the Share menu.
struct WorkbookExport: Transferable {
    let workbook: Workbook
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .excelWorkbook) { export in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(export.name).appendingPathExtension("xlsx")
            try XLSXWriter.data(for: export.workbook).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

extension WorkbookView {
    var toolbar: some View {
        HStack(spacing: 2) {
            ToolMenu(title: "\(Int((model.zoom * 100).rounded()))%", systemImage: "magnifyingglass") {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { level in
                    Button("\(Int(level * 100))%") { setZoom(level) }
                }
                Divider()
                Button("Zoom In (⌘=)") { setZoom(model.zoom + 0.1) }
                Button("Zoom Out (⌘−)") { setZoom(model.zoom - 0.1) }
                Divider()
                Button(model.showFormulas ? "Hide Formulas" : "Show Formulas") { model.showFormulas.toggle() }
                Button(sheet.showGridlines ? "Hide Gridlines" : "Show Gridlines") { toggleGridlines() }
            }
            ToolButton(title: "Undo", systemImage: "arrow.uturn.backward") { undoManager?.undo() }
            ToolButton(title: "Redo", systemImage: "arrow.uturn.forward") { undoManager?.redo() }

            Spacer(minLength: 12)

            ToolMenu(title: "Insert", systemImage: "plus.square") {
                Button("Rows Above") { insertRows(below: false) }
                Button("Rows Below") { insertRows(below: true) }
                Button("Columns Left") { insertColumns(right: false) }
                Button("Columns Right") { insertColumns(right: true) }
                Divider()
                Button("New Sheet") { addSheet() }
                Menu("New Sheet from Template") {
                    ForEach(SheetTemplate.allCases) { template in
                        Button("\(template.rawValue) — \(template.summary)") { insertTemplate(template) }
                    }
                }
                Divider()
                Button("Today's Date (⌘;)") { insertNow(time: false) }
                Button("Current Time (⇧⌘;)") { insertNow(time: true) }
            }
            ToolMenu(title: "Table", systemImage: "tablecells") {
                Menu("Table Style") {
                    ForEach(TableStylePreset.allCases) { style in Button(style.rawValue) { applyTableStyle(style) } }
                }
                Button("Summarize by Category") { summarizeByCategory() }
                Divider()
                Button(sheet.filter == nil ? "Add Filter (⇧⌘L)" : "Remove Filter (⇧⌘L)") { toggleFilter() }
                Button(sheet.frozenRows == 0 ? "Freeze Header Row" : "Unfreeze Rows") { setFrozenRows(sheet.frozenRows == 0 ? 1 : 0) }
                Divider()
                Button("Merge & Center") { mergeSelection(center: true, across: false) }
                Button("Unmerge Cells") { unmergeSelection() }
            }
            ToolMenu(title: "Chart", systemImage: "chart.bar.xaxis") {
                Button("Column") { insertChart(.column) }
                Button("Bar") { insertChart(.bar) }
                Button("Line") { insertChart(.line) }
                Button("Pie") { insertChart(.pie) }
            }
            ToolButton(title: "Text", systemImage: "textformat", help: "Add a text box") { insertTextBox() }
            ToolMenu(title: "Shape", systemImage: "square.on.circle") {
                Button("Rectangle") { insertShape(.rectangle) }
                Button("Rounded Rectangle") { insertShape(.roundedRectangle) }
                Button("Oval") { insertShape(.oval) }
                Button("Arrow") { insertShape(.arrow) }
            }
            ToolButton(title: "Media", systemImage: "photo", help: "Add a picture") { model.importingImage = true }
            ToolMenu(title: "Controls", systemImage: "checkmark.square") {
                Button("Checkbox") { applyControl(.checkbox) }
                Button("Star Rating") { applyControl(.rating) }
                Button("Pop-Up Menu…") { startControl(.popUp) }
                Button("Stepper…") { startControl(.stepper) }
                Button("Slider…") { startControl(.slider) }
                Divider()
                Button("Remove Control") { applyControl(nil) }
            }
            ToolMenu(title: "Formula", systemImage: "function") {
                Button("Sum") { autoSum("SUM") }
                Button("Average") { autoSum("AVERAGE") }
                Button("Count") { autoSum("COUNT") }
                Button("Maximum") { autoSum("MAX") }
                Button("Minimum") { autoSum("MIN") }
                Divider()
                ForEach(FunctionCategory.allCases, id: \.self) { category in
                    Menu(category.rawValue) {
                        ForEach(FunctionCatalog.all.filter { $0.category == category }) { info in
                            Button(info.name + " — " + info.summary) { insertFunction(info.name) }
                        }
                    }
                }
                if !workbook.definedNames.isEmpty {
                    Menu("Defined Names") {
                        ForEach(workbook.definedNames.indices, id: \.self) { index in
                            let name = workbook.definedNames[index]
                            Button("\(name.name)  =\(name.formula)") { insertName(name.name) }
                        }
                    }
                }
                Divider()
                Button(model.showFormulas ? "Hide Formulas" : "Show Formulas") { model.showFormulas.toggle() }
            }

            Spacer(minLength: 12)

            ToolButton(title: "Organize", systemImage: "line.3.horizontal.decrease.circle", isOn: model.inspector == .organize,
                       help: "Sort, filter and highlighting") { toggleInspector(.organize) }
            ToolButton(title: "Format", systemImage: "paintbrush", isOn: model.inspector == .format,
                       help: "Cell, text, table and object formatting") { toggleInspector(.format) }
            ShareLink(item: WorkbookExport(workbook: workbook, name: "Figures Workbook"),
                      preview: SharePreview("Figures Workbook.xlsx")) {
                ToolLabel(title: "Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .help("Send a copy as an Excel workbook")
        }
        .padding(.horizontal, 10)
        .frame(height: 56)
        .background(.bar)
    }

    func toggleInspector(_ pane: InspectorPane) {
        model.inspector = model.inspector == pane ? nil : pane
    }

    /// Types a defined name into the formula being edited, or starts a formula with it.
    func insertName(_ name: String) {
        if var current = editor {
            current.text += (current.text.isEmpty ? "=" : "") + name
            editor = current
            focusEditor(current)
        } else {
            beginEditing(at: selection.active, text: "=" + name)
        }
    }

    // MARK: - Sheet tabs

    var sheetTabs: some View {
        HStack(spacing: 6) {
            Button(action: addSheet) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("New Sheet")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(workbook.sheets.indices, id: \.self) { index in
                        let active = index == activeSheet
                        Text(workbook.sheets[index].name)
                            .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                            .foregroundStyle(active ? Color.primary : Color.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background {
                                if active {
                                    Capsule().fill(.background).shadow(color: .black.opacity(0.1), radius: 1.5, y: 0.5)
                                }
                            }
                            .contentShape(Capsule())
                            .onTapGesture(count: 2) { startRename(index) }
                            .onTapGesture { switchSheet(index) }
                            .contextMenu {
                                Button("Rename…") { startRename(index) }
                                Button("Delete", role: .destructive) { deleteSheet(index) }
                                    .disabled(workbook.sheets.count < 2)
                            }
                    }
                }
                .padding(.vertical, 3)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(Color.primary.opacity(0.035))
    }
}
