import Foundation

public enum XLSXError: Error, LocalizedError {
    case malformed(String)
    case unsupportedContainer

    public var errorDescription: String? {
        switch self {
        case .malformed(let detail):
            "The workbook could not be read: \(detail)."
        case .unsupportedContainer:
            "This workbook is password-protected or in the Excel 97–2003 (.xls) format. In Excel, remove the password or use Save As › Excel Workbook (.xlsx), then open it again."
        }
    }
}

/// Converts between column widths in points and Excel's character-based widths.
enum ColumnWidth {
    static func excelWidth(points: Double) -> Double { max(0, ((points - 5) / 7 * 100).rounded() / 100) }
    static func points(excelWidth: Double) -> Double { excelWidth * 7 + 5 }
}

/// Resolves SpreadsheetML `<color>` elements: RGB, theme slots with tint, and the indexed palette.
struct ColorResolver {
    /// Theme colors in SpreadsheetML index order: lt1, dk1, lt2, dk2, accent1–6, hlink, folHlink.
    var theme: [RGBColor]

    static let officeTheme = ["FFFFFF", "000000", "E7E6E6", "44546A", "4472C4", "ED7D31",
                              "A5A5A5", "FFC000", "5B9BD5", "70AD47", "0563C1", "954F72"].compactMap { RGBColor(hex: $0) }

    init(themeXML: XMLNodeTree?) {
        guard let scheme = themeXML?.child("themeElements")?.child("clrScheme") else {
            theme = Self.officeTheme
            return
        }
        func color(_ name: String) -> RGBColor? {
            guard let slot = scheme.child(name) else { return nil }
            if let hex = slot.child("srgbClr")?.attribute("val") { return RGBColor(hex: hex) }
            if let hex = slot.child("sysClr")?.attribute("lastClr") { return RGBColor(hex: hex) }
            return nil
        }
        let names = ["lt1", "dk1", "lt2", "dk2", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6", "hlink", "folHlink"]
        theme = names.enumerated().map { index, name in color(name) ?? Self.officeTheme[index] }
    }

    /// nil means automatic.
    func resolve(_ node: XMLNodeTree?) -> RGBColor? {
        guard let node, node.attribute("auto") != "1" else { return nil }
        var color: RGBColor?
        if let rgb = node.attribute("rgb") {
            color = RGBColor(hex: rgb)
        } else if let index = node.attribute("theme").flatMap(Int.init), theme.indices.contains(index) {
            color = theme[index]
        } else if let index = node.attribute("indexed").flatMap(Int.init) {
            color = IndexedColors.indexed(index)
        }
        guard let base = color else { return nil }
        if let tint = node.attribute("tint").flatMap(Double.init), tint != 0 { return Self.tinted(base, tint) }
        return base
    }

    /// Excel's tint: lighten toward white for positive values, darken for negative, in HSL lightness.
    static func tinted(_ color: RGBColor, _ tint: Double) -> RGBColor {
        let r = Double(color.red) / 255, g = Double(color.green) / 255, b = Double(color.blue) / 255
        let high = max(r, g, b), low = min(r, g, b)
        var hue = 0.0, saturation = 0.0
        var lightness = (high + low) / 2
        if high != low {
            let delta = high - low
            saturation = lightness > 0.5 ? delta / (2 - high - low) : delta / (high + low)
            switch high {
            case r: hue = (g - b) / delta + (g < b ? 6 : 0)
            case g: hue = (b - r) / delta + 2
            default: hue = (r - g) / delta + 4
            }
            hue /= 6
        }
        lightness = tint < 0 ? lightness * (1 + tint) : lightness * (1 - tint) + tint
        func channel(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        let (red, green, blue): (Double, Double, Double)
        if saturation == 0 {
            (red, green, blue) = (lightness, lightness, lightness)
        } else {
            let q = lightness < 0.5 ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation
            let p = 2 * lightness - q
            (red, green, blue) = (channel(p, q, hue + 1 / 3), channel(p, q, hue), channel(p, q, hue - 1 / 3))
        }
        func byte(_ x: Double) -> UInt8 { UInt8(min(255, max(0, (x * 255).rounded()))) }
        return RGBColor(red: byte(red), green: byte(green), blue: byte(blue))
    }
}

/// Excel's tint adjustment, as used for theme color shades.
public enum ColorTint {
    public static func apply(_ color: RGBColor, _ tint: Double) -> RGBColor { ColorResolver.tinted(color, tint) }
}

/// Parses `A1`, `A1:C3` and space-separated lists of them.
enum RangeList {
    static func parse(_ text: String) -> [CellRange] {
        text.split(separator: " ").compactMap { part in
            let ends = part.split(separator: ":").map(String.init)
            guard let start = ends.first.flatMap({ CellAddress(a1: $0.replacingOccurrences(of: "$", with: "")) }) else { return nil }
            let end = ends.count > 1 ? CellAddress(a1: ends[1].replacingOccurrences(of: "$", with: "")) ?? start : start
            return CellRange(start, end)
        }
    }
}

// MARK: - XML

/// A minimal element tree; element names are stored without namespace prefixes.
final class XMLNodeTree {
    let name: String
    let attributes: [String: String]
    var children: [XMLNodeTree] = []
    var text = ""

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    /// Looks up an attribute by local name, so `id` also finds `r:id`.
    func attribute(_ localName: String) -> String? {
        attributes[localName] ?? attributes.first { $0.key.hasSuffix(":" + localName) }?.value
    }

    /// Boolean attributes are "1"/"true"; absent uses the schema default.
    func flag(_ localName: String, default value: Bool = false) -> Bool {
        guard let raw = attribute(localName) else { return value }
        return raw == "1" || raw == "true"
    }

    func child(_ name: String) -> XMLNodeTree? { children.first { $0.name == name } }
    func children(_ name: String) -> [XMLNodeTree] { children.filter { $0.name == name } }
}

enum XML {
    static func parse(_ data: Data) throws -> XMLNodeTree {
        let builder = TreeBuilder()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = builder
        guard parser.parse(), let root = builder.root else {
            throw XLSXError.malformed(parser.parserError?.localizedDescription ?? "invalid XML")
        }
        return root
    }

    static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "\t", "\n", "\r": result.unicodeScalars.append(scalar)
            // XML 1.0 cannot represent other control characters.
            case _ where scalar.value < 0x20 || scalar.value == 0xFFFE || scalar.value == 0xFFFF: continue
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    private final class TreeBuilder: NSObject, XMLParserDelegate {
        var root: XMLNodeTree?
        private var stack: [XMLNodeTree] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
            let node = XMLNodeTree(name: localName, attributes: attributes)
            if let parent = stack.last { parent.children.append(node) } else { root = node }
            stack.append(node)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            stack.removeLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }
    }
}
