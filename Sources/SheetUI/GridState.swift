import Combine
import Foundation
import SheetCore

enum RibbonTab: String, CaseIterable, Identifiable {
    case home = "Home", insert = "Insert", formulas = "Formulas", data = "Data", view = "View"
    var id: String { rawValue }
}

enum PaletteTarget: String, Identifiable {
    case text, fill
    var id: String { rawValue }
}

/// Per-window grid state. A model object rather than `@State` properties because the
/// `@State` macro plugin ships only with Xcode, and this package also builds with the
/// Command Line Tools.
final class GridModel: ObservableObject {
    @Published var sheetIndex = 0
    @Published var selection = GridSelection(CellAddress(row: 0, column: 0))
    @Published var editor: CellEditor?
    @Published var renaming: Int?
    @Published var renameText = ""
    @Published var ribbonTab: RibbonTab = .home
    @Published var zoom = 1.0
    @Published var showFormulas = false
    @Published var findVisible = false
    @Published var findText = ""
    @Published var replaceText = ""
    @Published var matchCase = false
    @Published var findStatus = ""
    /// Text typed into the name box; nil while it shows the selection.
    @Published var nameBox: String?
    /// Column whose filter dropdown is open.
    @Published var filterColumn: Int?
    @Published var palette: PaletteTarget?
    @Published var chart: ChartRequest?
    @Published var message: String?
    /// The format Format Painter will apply to the next cell clicked.
    @Published var painter: CellFormat?
    @Published var ruleDraft: RuleDraft?
    @Published var formatDraft: FormatDraft?
    @Published var controlDraft: ControlDraft?
    /// The area an autofill drag would fill.
    @Published var fillPreview: CellRange?
    var clipboard: GridClipboard?
    var lastTap: (address: CellAddress, time: Date)?
    var resizing: (column: Int, startWidth: CGFloat)?
    var resizingRow: (row: Int, startHeight: CGFloat)?
    let cache = CalculationCache()
    let undoTarget = UndoTarget()
    let actions = GridActions()
    var layout: GridLayout?
    private var boundsCache: (version: UUID, sheet: Int, row: Int, column: Int)?

    /// The last used row and column of a sheet, computed once per workbook version.
    func bounds(of workbook: Workbook, sheet: Int) -> (row: Int, column: Int) {
        if let cached = boundsCache, cached.version == workbook.version, cached.sheet == sheet { return (cached.row, cached.column) }
        var row = 0
        var column = 0
        for address in workbook.sheets[sheet].cells.keys {
            row = max(row, address.row)
            column = max(column, address.column)
        }
        boundsCache = (workbook.version, sheet, row, column)
        return (row, column)
    }
}

/// The active cell plus the corner where a shift-selection started.
struct GridSelection: Equatable {
    var anchor: CellAddress
    var active: CellAddress

    init(_ address: CellAddress) {
        anchor = address
        active = address
    }

    init(anchor: CellAddress, active: CellAddress) {
        self.anchor = anchor
        self.active = active
    }

    var range: CellRange { CellRange(anchor, active) }
}

/// Text being typed into a cell, either in the cell itself or in the formula bar.
struct CellEditor: Equatable {
    let address: CellAddress
    var text: String
    let inCell: Bool
}

/// Cells copied from this window, kept so pasting can move formula references.
struct GridClipboard {
    let origin: CellAddress
    let inputs: [[String]]
    /// Inputs that reproduce the computed values, for Paste Values.
    let values: [[String]]
    let formats: [[CellFormat?]]
    /// The tab-separated text placed on the system pasteboard at the same time.
    let text: String
}

enum FocusField: Hashable {
    case grid, cellEditor, formulaBar, nameBox, find
}

/// Target object for undo registrations of a value-typed document.
final class UndoTarget {}

/// Reuses one calculator per workbook version, so redraws do not recalculate.
final class CalculationCache {
    private var version: UUID?
    private var calculator: Calculator?

    func calculator(for workbook: Workbook) -> Calculator {
        if let calculator, version == workbook.version { return calculator }
        // Keep every result the edit cannot have changed.
        let fresh = calculator.map { Calculator.updating($0, for: workbook) } ?? Calculator(workbook: workbook)
        calculator = fresh
        version = workbook.version
        return fresh
    }
}

/// A conditional formatting rule being set up in its dialog.
final class RuleDraft: ObservableObject, Identifiable {
    enum Kind: String {
        case greaterThan = "Greater Than", lessThan = "Less Than", between = "Between", equalTo = "Equal To"
        case textContains = "Text That Contains", top = "Top Items", topPercent = "Top Percent"
        case bottom = "Bottom Items", bottomPercent = "Bottom Percent", formula = "Use a Formula"
    }

    let id = UUID()
    let kind: Kind
    let range: CellRange
    @Published var first: String
    @Published var second = ""
    @Published var style: HighlightStyle = .lightRedFill

    init(kind: Kind, range: CellRange, first: String = "") {
        self.kind = kind
        self.range = range
        self.first = first
    }
}

/// Excel's preset highlight styles for conditional formatting.
enum HighlightStyle: String, CaseIterable, Identifiable {
    case lightRedFill = "Light Red Fill with Dark Red Text"
    case yellowFill = "Yellow Fill with Dark Yellow Text"
    case greenFill = "Green Fill with Dark Green Text"
    case lightRedOnly = "Light Red Fill"
    case redText = "Red Text"
    case bold = "Bold"

    var id: String { rawValue }

    var style: DifferentialStyle {
        switch self {
        case .lightRedFill: .lightRedFillDarkRedText
        case .yellowFill: .yellowFillDarkYellowText
        case .greenFill: .greenFillDarkGreenText
        case .lightRedOnly: .lightRedFill
        case .redText: .redText
        case .bold: DifferentialStyle(bold: true)
        }
    }
}

/// Settings for a pop-up menu, stepper or slider being added to cells.
final class ControlDraft: ObservableObject, Identifiable {
    enum Kind: String {
        case popUp = "Pop-Up Menu", stepper = "Stepper", slider = "Slider"
    }

    let id = UUID()
    let kind: Kind
    /// Pop-up choices, one per line.
    @Published var items: String
    @Published var minimum: String
    @Published var maximum: String
    @Published var step: String

    init(kind: Kind, items: [String] = []) {
        self.kind = kind
        self.items = items.joined(separator: "\n")
        minimum = "0"
        maximum = kind == .slider ? "100" : "10"
        step = "1"
    }
}

/// A custom number format being edited, with a sample value to preview it on.
final class FormatDraft: ObservableObject, Identifiable {
    let id = UUID()
    let sample: CellValue
    @Published var code: String

    init(code: String, sample: CellValue) {
        self.code = code
        self.sample = sample
    }
}
