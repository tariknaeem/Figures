import Foundation

public enum CellAlignment: String, CaseIterable, Sendable {
    case general, left, center, right
}

public enum CellVerticalAlignment: String, CaseIterable, Sendable {
    case top, center, bottom
}

public struct RGBColor: Hashable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Parses `RRGGBB` or Excel's `AARRGGBB`, with or without `#`.
    public init?(hex: String) {
        var digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if digits.count == 8 { digits.removeFirst(2) }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF), blue: UInt8(value & 0xFF))
    }

    public var hex: String { String(format: "%02X%02X%02X", red, green, blue) }
}

public enum BorderStyle: String, CaseIterable, Sendable {
    case thin, medium, thick, dashed, dotted, double, hair
    case mediumDashed, dashDot, mediumDashDot, dashDotDot, mediumDashDotDot, slantDashDot

    /// Line width in points as Excel draws it.
    public var width: Double {
        switch self {
        case .hair: 0.5
        case .thin, .dashed, .dotted, .dashDot, .dashDotDot: 1
        case .medium, .mediumDashed, .mediumDashDot, .mediumDashDotDot, .slantDashDot: 2
        case .thick, .double: 3
        }
    }

    /// Dash pattern in points; empty for solid lines.
    public var dash: [Double] {
        switch self {
        case .dashed, .mediumDashed: [4, 2]
        case .dotted, .hair: [1, 1]
        case .dashDot, .mediumDashDot, .slantDashDot: [4, 2, 1, 2]
        case .dashDotDot, .mediumDashDotDot: [4, 2, 1, 2, 1, 2]
        default: []
        }
    }
}

public struct BorderLine: Hashable, Sendable {
    public var style: BorderStyle
    /// nil draws in the automatic (black) color.
    public var color: RGBColor?

    public init(_ style: BorderStyle = .thin, color: RGBColor? = nil) {
        self.style = style
        self.color = color
    }
}

public struct CellBorder: Hashable, Sendable {
    public var top: BorderLine?
    public var bottom: BorderLine?
    public var left: BorderLine?
    public var right: BorderLine?

    public init(top: BorderLine? = nil, bottom: BorderLine? = nil, left: BorderLine? = nil, right: BorderLine? = nil) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }

    public static func all(_ line: BorderLine) -> CellBorder { CellBorder(top: line, bottom: line, left: line, right: line) }

    public var isEmpty: Bool { top == nil && bottom == nil && left == nil && right == nil }
}

/// How a cell looks. Font name and size of nil use the workbook's default font.
public struct CellFormat: Hashable, Sendable {
    public var fontName: String?
    public var fontSize: Double?
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool
    public var strikethrough: Bool
    /// nil is Excel's automatic text color.
    public var textColor: RGBColor?
    public var fillColor: RGBColor?
    public var border: CellBorder
    public var alignment: CellAlignment
    public var verticalAlignment: CellVerticalAlignment
    public var wrapText: Bool
    public var indent: Int
    /// An Excel number format code such as `#,##0.00` or `m/d/yyyy`.
    public var numberFormat: String

    public init(
        fontName: String? = nil, fontSize: Double? = nil,
        bold: Bool = false, italic: Bool = false, underline: Bool = false, strikethrough: Bool = false,
        textColor: RGBColor? = nil, fillColor: RGBColor? = nil, border: CellBorder = CellBorder(),
        alignment: CellAlignment = .general, verticalAlignment: CellVerticalAlignment = .bottom,
        wrapText: Bool = false, indent: Int = 0, numberFormat: String = "General"
    ) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.textColor = textColor
        self.fillColor = fillColor
        self.border = border
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
        self.wrapText = wrapText
        self.indent = indent
        self.numberFormat = numberFormat
    }

    public var isDefault: Bool { self == CellFormat() }
}

/// The number formats offered in the ribbon, as Excel format codes.
public enum NumberFormatPreset: String, CaseIterable, Identifiable, Sendable {
    case general = "General"
    case number = "Number"
    case currency = "Currency"
    case accounting = "Accounting"
    case shortDate = "Short Date"
    case longDate = "Long Date"
    case isoDate = "ISO Date"
    case time = "Time"
    case duration = "Duration"
    case percentage = "Percentage"
    case fraction = "Fraction"
    case scientific = "Scientific"
    case text = "Text"

    public var id: String { rawValue }

    public var code: String {
        switch self {
        case .general: "General"
        case .number: "#,##0.00"
        case .currency: "\"$\"#,##0.00"
        case .accounting: #"_("$"* #,##0.00_);_("$"* \(#,##0.00\);_("$"* "-"??_);_(@_)"#
        case .shortDate: "m/d/yyyy"
        case .longDate: "dddd, mmmm d, yyyy"
        case .isoDate: "yyyy-mm-dd"
        case .time: "h:mm:ss AM/PM"
        case .duration: "[h]:mm:ss"
        case .percentage: "0.00%"
        case .fraction: "# ?/?"
        case .scientific: "0.00E+00"
        case .text: "@"
        }
    }

    /// A sample of what the format shows, for menus.
    public var example: String {
        let sample: Double = switch self {
        case .shortDate, .longDate, .isoDate: 46_313
        case .time: 0.6875
        case .duration: 1.5625
        case .percentage: 0.125
        case .fraction: 1.75
        default: 1234.5
        }
        return ExcelNumberFormat.format(.number(sample), code: code).text
    }

    public static func matching(_ code: String) -> NumberFormatPreset? {
        allCases.first { $0.code == code }
    }
}

extension CellValue {
    /// The value as shown with a cell's number format.
    public func formatted(_ format: CellFormat?) -> String {
        ExcelNumberFormat.format(self, code: format?.numberFormat ?? "General").text
    }
}
