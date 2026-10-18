import Charts
import Combine
import SheetCore
import SwiftUI

extension Color {
    init(_ rgb: SheetCore.RGBColor) {
        self.init(red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }
}

/// Excel's theme and standard colors.
struct ColorPalette: View {
    let title: String
    let noneTitle: String
    let onPick: (SheetCore.RGBColor?) -> Void

    private static let rows: [[String]] = [
        ["FFFFFF", "000000", "E7E6E6", "44546A", "4472C4", "ED7D31", "A5A5A5", "FFC000", "5B9BD5", "70AD47"],
        ["F2F2F2", "7F7F7F", "D0CECE", "D6DCE4", "D9E1F2", "FCE4D6", "EDEDED", "FFF2CC", "DDEBF7", "E2EFDA"],
        ["D9D9D9", "595959", "AEAAAA", "ACB9CA", "B4C6E7", "F8CBAD", "DBDBDB", "FFE699", "BDD7EE", "C6E0B4"],
        ["BFBFBF", "404040", "757171", "8497B0", "8EA9DB", "F4B084", "C9C9C9", "FFD966", "9BC2E6", "A9D08E"],
        ["C00000", "FF0000", "FFC000", "FFFF00", "92D050", "00B050", "00B0F0", "0070C0", "002060", "7030A0"],
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Button(noneTitle) { onPick(nil) }
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(Self.rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(Self.rows[row], id: \.self) { hex in
                            let color = SheetCore.RGBColor(hex: hex)!
                            Button { onPick(color) } label: {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(color))
                                    .frame(width: 18, height: 18)
                                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.gray.opacity(0.4)))
                            }
                            .buttonStyle(.plain)
                            .help("#" + hex)
                        }
                    }
                }
            }
        }
        .padding(12)
    }
}

final class FilterPopoverState: ObservableObject {
    @Published var search = ""
    @Published var selected: Set<String>

    init(selected: Set<String>) {
        self.selected = selected
    }
}

/// The dropdown on a filtered header cell: sort, search and a checklist of values.
struct FilterPopover: View {
    /// Distinct shown values in the column; "" stands for blanks.
    let values: [String]
    let onSort: (Bool) -> Void
    let onApply: (Set<String>?) -> Void
    let onCancel: () -> Void
    @StateObject private var state: FilterPopoverState

    init(values: [String], allowed: Set<String>?, onSort: @escaping (Bool) -> Void,
         onApply: @escaping (Set<String>?) -> Void, onCancel: @escaping () -> Void) {
        self.values = values
        self.onSort = onSort
        self.onApply = onApply
        self.onCancel = onCancel
        _state = StateObject(wrappedValue: FilterPopoverState(selected: allowed ?? Set(values)))
    }

    private func label(_ value: String) -> String { value.isEmpty ? "(Blanks)" : value }

    private var visible: [String] {
        state.search.isEmpty ? values : values.filter { label($0).localizedCaseInsensitiveContains(state.search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { onSort(true) } label: { Label("Sort A to Z", systemImage: "arrow.up") }
                .buttonStyle(.plain)
            Button { onSort(false) } label: { Label("Sort Z to A", systemImage: "arrow.down") }
                .buttonStyle(.plain)
            Divider()
            TextField("Search", text: $state.search)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    let shown = visible
                    checkRow("(Select All)", isOn: shown.allSatisfy(state.selected.contains)) {
                        if shown.allSatisfy(state.selected.contains) {
                            state.selected.subtract(shown)
                        } else {
                            state.selected.formUnion(shown)
                        }
                    }
                    ForEach(shown, id: \.self) { value in
                        checkRow(label(value), isOn: state.selected.contains(value)) {
                            if state.selected.contains(value) {
                                state.selected.remove(value)
                            } else {
                                state.selected.insert(value)
                            }
                        }
                    }
                }
            }
            .frame(height: 190)
            HStack {
                Button("Clear Filter") { onApply(nil) }
                Spacer()
                Button("Cancel", action: onCancel)
                Button("OK") { onApply(state.selected.isSuperset(of: values) ? nil : state.selected) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.selected.isEmpty)
            }
        }
        .padding(12)
        .frame(width: 270)
    }

    private func checkRow(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

enum ChartKind: String, CaseIterable, Identifiable {
    case column = "Column", bar = "Bar", line = "Line", pie = "Pie"
    var id: String { rawValue }
}

struct ChartSeries {
    let name: String
    let values: [Double]
}

struct ChartRequest: Identifiable {
    let id = UUID()
    let kind: ChartKind
    let title: String
    let categories: [String]
    let series: [ChartSeries]
}

private struct ChartPoint: Identifiable {
    let id: Int
    let category: String
    let series: String
    let value: Double
}

final class ChartPanelState: ObservableObject {
    @Published var kind: ChartKind

    init(kind: ChartKind) {
        self.kind = kind
    }
}

/// A chart of the selected cells, shown in a sheet.
struct ChartPanel: View {
    let request: ChartRequest
    @StateObject private var state: ChartPanelState
    @Environment(\.dismiss) private var dismiss

    init(request: ChartRequest) {
        self.request = request
        _state = StateObject(wrappedValue: ChartPanelState(kind: request.kind))
    }

    private var points: [ChartPoint] {
        var points: [ChartPoint] = []
        for series in request.series {
            for (index, category) in request.categories.enumerated() where index < series.values.count {
                points.append(ChartPoint(id: points.count, category: category, series: series.name, value: series.values[index]))
            }
        }
        return points
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(request.title).font(.headline)
                Spacer()
                Picker("Chart type", selection: $state.kind) {
                    ForEach(ChartKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 280)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            chart
                .frame(minWidth: 560, minHeight: 360)
            Text("Charts are previews of the current values and are not saved in the workbook.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    @ViewBuilder
    private var chart: some View {
        let points = points
        switch state.kind {
        case .column:
            Chart(points) { point in
                BarMark(x: .value("Category", point.category), y: .value("Value", point.value))
                    .foregroundStyle(by: .value("Series", point.series))
                    .position(by: .value("Series", point.series))
            }
        case .bar:
            Chart(points) { point in
                BarMark(x: .value("Value", point.value), y: .value("Category", point.category))
                    .foregroundStyle(by: .value("Series", point.series))
                    .position(by: .value("Series", point.series))
            }
        case .line:
            Chart(points) { point in
                LineMark(x: .value("Category", point.category), y: .value("Value", point.value))
                    .foregroundStyle(by: .value("Series", point.series))
                    .symbol(by: .value("Series", point.series))
            }
        case .pie:
            // A pie shows the first series only, as in Excel.
            Chart(points.filter { $0.series == request.series.first?.name }) { point in
                SectorMark(angle: .value("Value", max(point.value, 0)), angularInset: 1)
                    .foregroundStyle(by: .value("Category", point.category))
            }
        }
    }
}

/// A cell's border lines with Excel's widths, dashes, double lines and colors.
struct CellBorderLines: View {
    let border: CellBorder
    let scale: CGFloat

    var body: some View {
        Canvas { context, size in
            func draw(_ line: BorderLine?, from a: CGPoint, to b: CGPoint, inset: CGVector) {
                guard let line else { return }
                let color = line.color.map { Color($0) } ?? Color.black
                let width = max(1, CGFloat(line.style.width) * scale)
                let style = StrokeStyle(lineWidth: line.style == .double ? max(1, scale) : width,
                                        dash: line.style.dash.map { CGFloat($0) * scale })
                func stroke(_ offset: CGFloat) {
                    var path = Path()
                    path.move(to: CGPoint(x: a.x + inset.dx * offset, y: a.y + inset.dy * offset))
                    path.addLine(to: CGPoint(x: b.x + inset.dx * offset, y: b.y + inset.dy * offset))
                    context.stroke(path, with: .color(color), style: style)
                }
                if line.style == .double {
                    stroke(0.5)
                    stroke(2.5 * scale)
                } else {
                    stroke(width / 2)
                }
            }
            let (w, h) = (size.width, size.height)
            draw(border.top, from: CGPoint(x: 0, y: 0), to: CGPoint(x: w, y: 0), inset: CGVector(dx: 0, dy: 1))
            draw(border.bottom, from: CGPoint(x: 0, y: h), to: CGPoint(x: w, y: h), inset: CGVector(dx: 0, dy: -1))
            draw(border.left, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: h), inset: CGVector(dx: 1, dy: 0))
            draw(border.right, from: CGPoint(x: w, y: 0), to: CGPoint(x: w, y: h), inset: CGVector(dx: -1, dy: 0))
        }
        .allowsHitTesting(false)
    }
}

/// The conditional formatting dialog for rules that need a value.
struct RuleSheet: View {
    @ObservedObject var draft: RuleDraft
    let onApply: (RuleDraft) -> Void
    @Environment(\.dismiss) private var dismiss

    private var prompt: String {
        switch draft.kind {
        case .greaterThan: "Format cells that are GREATER THAN:"
        case .lessThan: "Format cells that are LESS THAN:"
        case .between: "Format cells that are BETWEEN:"
        case .equalTo: "Format cells that are EQUAL TO:"
        case .textContains: "Format cells that contain the text:"
        case .top, .topPercent: "Format cells that rank in the TOP:"
        case .bottom, .bottomPercent: "Format cells that rank in the BOTTOM:"
        case .formula: "Format cells where this formula is true:"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.kind.rawValue).font(.headline)
            Text(prompt)
            HStack {
                TextField(draft.kind == .formula ? "=MOD(ROW(),2)=0" : "Value or =cell", text: $draft.first)
                    .textFieldStyle(.roundedBorder)
                if draft.kind == .between {
                    Text("and")
                    TextField("Value", text: $draft.second)
                        .textFieldStyle(.roundedBorder)
                }
                if draft.kind == .topPercent || draft.kind == .bottomPercent { Text("%") }
            }
            Picker("with", selection: $draft.style) {
                ForEach(HighlightStyle.allCases) { Text($0.rawValue).tag($0) }
            }
            Text("Applies to \(draft.range.a1). Formulas are written for the top-left cell, \(draft.range.start.a1).")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("OK") {
                    onApply(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.first.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

/// Edit an Excel number format code with a live preview.
struct FormatSheet: View {
    @ObservedObject var draft: FormatDraft
    let onApply: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private static let examples = [
        "0", "0.00", "#,##0", "#,##0.00", "#,##0.00;[Red](#,##0.00)", "\"$\"#,##0.00", "0%", "0.00%",
        "0.00E+00", "# ?/?", "m/d/yyyy", "d-mmm-yy", "mmmm d, yyyy", "dddd", "h:mm AM/PM", "[h]:mm:ss",
        "#,##0,\"K\"", "@",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Number Format").font(.headline)
            TextField("Format code", text: $draft.code)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            let preview = ExcelNumberFormat.format(draft.sample, code: draft.code.isEmpty ? "General" : draft.code)
            HStack {
                Text("Sample:").foregroundStyle(.secondary)
                Text(preview.text)
                    .foregroundStyle(preview.color.map { Color($0) } ?? Color.primary)
                    .font(.system(.body, design: .monospaced))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Self.examples, id: \.self) { code in
                        Button {
                            draft.code = code
                        } label: {
                            HStack {
                                Text(code).font(.system(size: 12, design: .monospaced))
                                Spacer()
                                Text(ExcelNumberFormat.format(draft.sample.isNumber ? draft.sample : .number(1234.5), code: code).text)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 200)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("OK") {
                    onApply(draft.code.isEmpty ? "General" : draft.code)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

/// Excel's built-in cell styles.
enum CellStylePreset: String, CaseIterable, Identifiable {
    case normal = "Normal", good = "Good", bad = "Bad", neutral = "Neutral"
    case title = "Title", heading1 = "Heading 1", heading2 = "Heading 2", heading3 = "Heading 3", total = "Total"
    case input = "Input", output = "Output", calculation = "Calculation", note = "Note", warning = "Warning Text"
    case accent1 = "Accent 1", accent2 = "Accent 2", accent4 = "Accent 4", accent6 = "Accent 6"

    var id: String { rawValue }

    func apply(to format: CellFormat) -> CellFormat {
        func color(_ hex: String) -> SheetCore.RGBColor? { SheetCore.RGBColor(hex: hex) }
        var f = format
        switch self {
        case .normal:
            f = CellFormat(numberFormat: format.numberFormat)
        case .good:
            (f.fillColor, f.textColor) = (color("C6EFCE"), color("006100"))
        case .bad:
            (f.fillColor, f.textColor) = (color("FFC7CE"), color("9C0006"))
        case .neutral:
            (f.fillColor, f.textColor) = (color("FFEB9C"), color("9C5700"))
        case .title:
            (f.bold, f.fontSize, f.textColor) = (true, 18, color("44546A"))
        case .heading1:
            (f.bold, f.fontSize, f.textColor) = (true, 15, color("44546A"))
            f.border.bottom = BorderLine(.thick, color: color("4472C4"))
        case .heading2:
            (f.bold, f.fontSize, f.textColor) = (true, 13, color("44546A"))
            f.border.bottom = BorderLine(.thick, color: color("A9C4EB"))
        case .heading3:
            (f.bold, f.textColor) = (true, color("44546A"))
            f.border.bottom = BorderLine(.medium, color: color("8EA9DB"))
        case .total:
            f.bold = true
            f.border.top = BorderLine(.thin, color: color("4472C4"))
            f.border.bottom = BorderLine(.double, color: color("4472C4"))
        case .input:
            (f.fillColor, f.textColor) = (color("FFCC99"), color("3F3F76"))
            f.border = .all(BorderLine(.thin, color: color("7F7F7F")))
        case .output:
            (f.fillColor, f.textColor, f.bold) = (color("F2F2F2"), color("3F3F3F"), true)
            f.border = .all(BorderLine(.thin, color: color("3F3F3F")))
        case .calculation:
            (f.fillColor, f.textColor, f.bold) = (color("F2F2F2"), color("FA7D00"), true)
            f.border = .all(BorderLine(.thin, color: color("7F7F7F")))
        case .note:
            f.fillColor = color("FFFFCC")
            f.border = .all(BorderLine(.thin, color: color("B2B2B2")))
        case .warning:
            f.textColor = color("FF0000")
        case .accent1:
            (f.fillColor, f.textColor) = (color("4472C4"), color("FFFFFF"))
        case .accent2:
            (f.fillColor, f.textColor) = (color("ED7D31"), color("FFFFFF"))
        case .accent4:
            (f.fillColor, f.textColor) = (color("FFC000"), color("FFFFFF"))
        case .accent6:
            (f.fillColor, f.textColor) = (color("70AD47"), color("FFFFFF"))
        }
        return f
    }
}

/// Choices for a pop-up menu, or limits for a stepper or slider.
struct ControlSheet: View {
    @ObservedObject var draft: ControlDraft
    let onApply: (CellControl) -> Void
    @Environment(\.dismiss) private var dismiss

    private var control: CellControl? {
        switch draft.kind {
        case .popUp:
            var seen = Set<String>()
            let items = draft.items.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && seen.insert($0).inserted }
            return items.isEmpty ? nil : .popUp(.items(items))
        case .stepper, .slider:
            guard let low = Double(draft.minimum), let high = Double(draft.maximum), let step = Double(draft.step),
                  high > low, step > 0 else { return nil }
            return draft.kind == .stepper ? .stepper(minimum: low, maximum: high, step: step) : .slider(minimum: low, maximum: high, step: step)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.kind.rawValue).font(.headline)
            if draft.kind == .popUp {
                Text("Choices, one per line:")
                TextEditor(text: $draft.items)
                    .font(.system(size: 13))
                    .frame(height: 150)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
            } else {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        Text("Minimum")
                        TextField("0", text: $draft.minimum).textFieldStyle(.roundedBorder).frame(width: 100)
                    }
                    GridRow {
                        Text("Maximum")
                        TextField("100", text: $draft.maximum).textFieldStyle(.roundedBorder).frame(width: 100)
                    }
                    GridRow {
                        Text("Step")
                        TextField("1", text: $draft.step).textFieldStyle(.roundedBorder).frame(width: 100)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("OK") {
                    if let control {
                        onApply(control)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(control == nil)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

/// Quick table looks: a colored header row and banded body rows, as Numbers' table styles.
enum TableStylePreset: String, CaseIterable, Identifiable {
    case blue = "Blue", green = "Green", orange = "Orange", purple = "Purple", gray = "Gray", plain = "Plain"

    var id: String { rawValue }

    var colors: (header: String, band: String, line: String) {
        switch self {
        case .blue: ("4472C4", "D9E1F2", "8EA9DB")
        case .green: ("70AD47", "E2EFDA", "A9D08E")
        case .orange: ("ED7D31", "FCE4D6", "F4B084")
        case .purple: ("7030A0", "E4DFEC", "B4A7D6")
        case .gray: ("595959", "EDEDED", "BFBFBF")
        case .plain: ("FFFFFF", "FFFFFF", "BFBFBF")
        }
    }
}
