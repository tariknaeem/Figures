import Foundation

/// A chart, text box, shape or image floating over a sheet, as on a Numbers canvas.
/// Positions and sizes are in points at 100% zoom, measured from the top-left corner of cell A1.
public struct CanvasObject: Hashable, Sendable, Identifiable {
    public enum ShapeKind: String, CaseIterable, Sendable {
        case rectangle, roundedRectangle, oval, arrow
    }

    public enum ChartKind: String, CaseIterable, Sendable {
        case column, bar, line, pie
    }

    public enum Kind: Hashable, Sendable {
        /// A live chart of a range; a header row names series and a text first column labels categories.
        case chart(ChartKind, range: CellRange, title: String)
        case text(String)
        case shape(ShapeKind)
        /// PNG or JPEG bytes.
        case image(Data)
    }

    public var id: UUID
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var kind: Kind
    public var fill: RGBColor?
    public var stroke: RGBColor?
    public var textColor: RGBColor?
    public var fontSize: Double
    public var bold: Bool

    public init(id: UUID = UUID(), x: Double, y: Double, width: Double, height: Double, kind: Kind,
                fill: RGBColor? = nil, stroke: RGBColor? = nil, textColor: RGBColor? = nil, fontSize: Double = 14, bold: Bool = false) {
        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.kind = kind
        self.fill = fill
        self.stroke = stroke
        self.textColor = textColor
        self.fontSize = fontSize
        self.bold = bold
    }
}

/// Labels and values of a chart's range, ready to draw.
public struct ChartData: Equatable, Sendable {
    public struct Series: Equatable, Sendable {
        public let name: String
        public let values: [Double]
    }

    public let categories: [String]
    public let series: [Series]

    public init(categories: [String], series: [Series]) {
        self.categories = categories
        self.series = series
    }

    public var isEmpty: Bool { series.allSatisfy { $0.values.allSatisfy { $0 == 0 } } }
}

extension Calculator {
    /// Reads a chart range: a first row with text names the series, a first column with text labels the categories.
    public func chartData(_ range: CellRange, sheet: Int) -> ChartData {
        func value(_ row: Int, _ column: Int) -> CellValue { self.value(sheet: sheet, at: CellAddress(row: row, column: column)) }
        func isText(_ v: CellValue) -> Bool {
            if case .text = v { return true }
            return false
        }
        // Charts read at most a few thousand cells; larger ranges are cut to keep drawing fast.
        let lastRow = min(range.end.row, range.start.row + 500)
        let lastColumn = min(range.end.column, range.start.column + 20)
        let headerRow = lastRow > range.start.row && (range.start.column...lastColumn).contains { isText(value(range.start.row, $0)) }
        let firstData = headerRow ? range.start.row + 1 : range.start.row
        guard firstData <= lastRow else { return ChartData(categories: [], series: []) }
        let rows = Array(firstData...lastRow)
        let labelColumn = lastColumn > range.start.column && rows.contains { !value($0, range.start.column).isNumber }
        let firstSeries = labelColumn ? range.start.column + 1 : range.start.column
        guard firstSeries <= lastColumn else { return ChartData(categories: [], series: []) }
        let series = (firstSeries...lastColumn).map { column in
            ChartData.Series(
                name: headerRow ? displayText(sheet: sheet, at: CellAddress(row: range.start.row, column: column))
                    : "Column " + CellAddress.columnName(column),
                values: rows.map { value($0, column).numberValue ?? 0 }
            )
        }
        let categories = rows.map { row in
            labelColumn ? displayText(sheet: sheet, at: CellAddress(row: row, column: range.start.column)) : String(row + 1)
        }
        return ChartData(categories: categories, series: series)
    }
}

extension StructuralChange {
    /// Keeps charts pointing at the same data when rows or columns are inserted or deleted.
    func adjust(_ object: CanvasObject) -> CanvasObject {
        guard case .chart(let kind, let range, let title) = object.kind, let moved = adjust(range) else { return object }
        var adjusted = object
        adjusted.kind = .chart(kind, range: moved, title: title)
        return adjusted
    }
}
