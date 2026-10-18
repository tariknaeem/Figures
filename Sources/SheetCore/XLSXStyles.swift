import Foundation

/// Collects distinct cell formats and conditional styles, and builds styles.xml for them.
struct StyleTable {
    private struct Font: Hashable {
        var name: String
        var size: Double
        var bold = false, italic = false, underline = false, strikethrough = false
        var color: RGBColor?
    }

    let defaultFontName: String
    let defaultFontSize: Double
    private var formats: [CellFormat] = [CellFormat()]
    private var differentialStyles: [DifferentialStyle] = []

    init(defaultFontName: String, defaultFontSize: Double) {
        self.defaultFontName = defaultFontName
        self.defaultFontSize = defaultFontSize
    }

    mutating func index(for format: CellFormat) -> Int {
        if let existing = formats.firstIndex(of: format) { return existing }
        formats.append(format)
        return formats.count - 1
    }

    mutating func dxfIndex(for style: DifferentialStyle) -> Int {
        if let existing = differentialStyles.firstIndex(of: style) { return existing }
        differentialStyles.append(style)
        return differentialStyles.count - 1
    }

    private func font(_ format: CellFormat) -> Font {
        Font(name: format.fontName ?? defaultFontName, size: format.fontSize ?? defaultFontSize,
             bold: format.bold, italic: format.italic, underline: format.underline,
             strikethrough: format.strikethrough, color: format.textColor)
    }

    private static func colorXML(_ color: RGBColor?, element: String = "color") -> String {
        color.map { #"<\#(element) rgb="FF\#($0.hex)"/>"# } ?? #"<\#(element) auto="1"/>"#
    }

    var xml: String {
        var fonts: [Font] = [font(CellFormat())]
        var fills: [RGBColor] = []
        var borders: [CellBorder] = [CellBorder()]
        var customCodes: [String] = []
        var xfs: [(numFmt: Int, font: Int, fill: Int, border: Int, format: CellFormat)] = []

        for format in formats {
            let font = font(format)
            if !fonts.contains(font) { fonts.append(font) }
            if let fill = format.fillColor, !fills.contains(fill) { fills.append(fill) }
            if !borders.contains(format.border) { borders.append(format.border) }
            var numFmt = ExcelNumberFormat.builtInID(for: format.numberFormat) ?? -1
            if numFmt < 0 {
                if !customCodes.contains(format.numberFormat) { customCodes.append(format.numberFormat) }
                numFmt = 164 + customCodes.firstIndex(of: format.numberFormat)!
            }
            // Fill ids 0 and 1 are reserved for "none" and "gray125".
            let fill = format.fillColor.map { 2 + fills.firstIndex(of: $0)! } ?? 0
            xfs.append((numFmt, fonts.firstIndex(of: font)!, fill, borders.firstIndex(of: format.border)!, format))
        }

        var xml = XLSXWriter.header + #"<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">"#
        if !customCodes.isEmpty {
            xml += #"<numFmts count="\#(customCodes.count)">"#
            for (i, code) in customCodes.enumerated() {
                xml += #"<numFmt numFmtId="\#(164 + i)" formatCode="\#(XML.escape(code))"/>"#
            }
            xml += "</numFmts>"
        }
        xml += #"<fonts count="\#(fonts.count)">"#
        for font in fonts {
            xml += "<font>" + (font.bold ? "<b/>" : "") + (font.italic ? "<i/>" : "") + (font.strikethrough ? "<strike/>" : "")
            xml += (font.underline ? "<u/>" : "") + #"<sz val="\#(NumberText.roundTrip(font.size))"/>"#
            if let color = font.color { xml += #"<color rgb="FF\#(color.hex)"/>"# }
            xml += #"<name val="\#(XML.escape(font.name))"/></font>"#
        }
        xml += "</fonts>"
        xml += #"<fills count="\#(fills.count + 2)"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>"#
        for fill in fills {
            xml += #"<fill><patternFill patternType="solid"><fgColor rgb="FF\#(fill.hex)"/><bgColor indexed="64"/></patternFill></fill>"#
        }
        xml += "</fills>"
        xml += #"<borders count="\#(borders.count)">"#
        for border in borders {
            xml += "<border>"
            for (line, name) in [(border.left, "left"), (border.right, "right"), (border.top, "top"), (border.bottom, "bottom")] {
                if let line {
                    xml += #"<\#(name) style="\#(line.style.rawValue)">\#(Self.colorXML(line.color))</\#(name)>"#
                } else {
                    xml += "<\(name)/>"
                }
            }
            xml += "<diagonal/></border>"
        }
        xml += "</borders>"
        xml += #"<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>"#
        xml += #"<cellXfs count="\#(xfs.count)">"#
        for xf in xfs {
            xml += #"<xf numFmtId="\#(xf.numFmt)" fontId="\#(xf.font)" fillId="\#(xf.fill)" borderId="\#(xf.border)" xfId="0""#
            if xf.numFmt != 0 { xml += #" applyNumberFormat="1""# }
            if xf.font != 0 { xml += #" applyFont="1""# }
            if xf.fill != 0 { xml += #" applyFill="1""# }
            if xf.border != 0 { xml += #" applyBorder="1""# }
            let format = xf.format
            var alignment = ""
            if format.alignment != .general { alignment += #" horizontal="\#(format.alignment.rawValue)""# }
            if format.verticalAlignment != .bottom { alignment += #" vertical="\#(format.verticalAlignment.rawValue)""# }
            if format.wrapText { alignment += #" wrapText="1""# }
            if format.indent > 0 { alignment += #" indent="\#(format.indent)""# }
            xml += alignment.isEmpty ? "/>" : #" applyAlignment="1"><alignment\#(alignment)/></xf>"#
        }
        xml += "</cellXfs>"
        xml += #"<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>"#
        if !differentialStyles.isEmpty {
            xml += #"<dxfs count="\#(differentialStyles.count)">"#
            for style in differentialStyles {
                xml += "<dxf>"
                var font = ""
                if let bold = style.bold { font += bold ? "<b/>" : #"<b val="0"/>"# }
                if let italic = style.italic { font += italic ? "<i/>" : #"<i val="0"/>"# }
                if let strike = style.strikethrough { font += strike ? "<strike/>" : #"<strike val="0"/>"# }
                if let underline = style.underline { font += underline ? "<u/>" : #"<u val="none"/>"# }
                if let color = style.textColor { font += #"<color rgb="FF\#(color.hex)"/>"# }
                if !font.isEmpty { xml += "<font>\(font)</font>" }
                if let fill = style.fillColor { xml += #"<fill><patternFill><bgColor rgb="FF\#(fill.hex)"/></patternFill></fill>"# }
                xml += "</dxf>"
            }
            xml += "</dxfs>"
        }
        return xml + "</styleSheet>"
    }
}

/// Reads styles.xml into cell formats relative to the workbook's default font, plus conditional styles.
struct StyleReader {
    private(set) var formats: [CellFormat?] = []
    private(set) var differentialStyles: [DifferentialStyle] = []
    private(set) var defaultFontName = "Calibri"
    private(set) var defaultFontSize = 11.0

    init(_ root: XMLNodeTree?, colors: ColorResolver) {
        guard let root else { return }
        var customCodes: [Int: String] = [:]
        for numFmt in root.child("numFmts")?.children("numFmt") ?? [] {
            if let id = numFmt.attribute("numFmtId").flatMap(Int.init) { customCodes[id] = numFmt.attribute("formatCode") ?? "General" }
        }

        struct Font {
            var name: String?
            var size: Double?
            var bold = false, italic = false, underline = false, strikethrough = false
            var color: RGBColor?
        }
        func on(_ node: XMLNodeTree?) -> Bool {
            guard let node else { return false }
            return !["0", "false", "none"].contains(node.attribute("val") ?? "")
        }
        let fonts: [Font] = (root.child("fonts")?.children("font") ?? []).map { node in
            Font(name: node.child("name")?.attribute("val"), size: node.child("sz")?.attribute("val").flatMap(Double.init),
                 bold: on(node.child("b")), italic: on(node.child("i")), underline: on(node.child("u")),
                 strikethrough: on(node.child("strike")), color: colors.resolve(node.child("color")))
        }
        let base = fonts.first ?? Font()
        defaultFontName = base.name ?? "Calibri"
        defaultFontSize = base.size ?? 11

        let fills: [RGBColor?] = (root.child("fills")?.children("fill") ?? []).map { fill in
            guard let pattern = fill.child("patternFill"), let type = pattern.attribute("patternType"), type != "none" else { return nil }
            return colors.resolve(pattern.child("fgColor")) ?? (type == "solid" ? nil : colors.resolve(pattern.child("bgColor")))
        }
        let borders: [CellBorder] = (root.child("borders")?.children("border") ?? []).map { node in
            func line(_ name: String) -> BorderLine? {
                guard let side = node.child(name), let style = side.attribute("style"), style != "none" else { return nil }
                return BorderLine(BorderStyle(rawValue: style) ?? .thin, color: colors.resolve(side.child("color")))
            }
            return CellBorder(top: line("top"), bottom: line("bottom"), left: line("left"), right: line("right"))
        }

        formats = (root.child("cellXfs")?.children("xf") ?? []).map { xf in
            var format = CellFormat()
            if let id = xf.attribute("fontId").flatMap(Int.init), fonts.indices.contains(id) {
                let font = fonts[id]
                format.fontName = font.name == base.name ? nil : font.name
                format.fontSize = font.size == base.size ? nil : font.size
                (format.bold, format.italic) = (font.bold, font.italic)
                (format.underline, format.strikethrough) = (font.underline, font.strikethrough)
                format.textColor = font.color == base.color ? nil : font.color
            }
            if let id = xf.attribute("fillId").flatMap(Int.init), fills.indices.contains(id) { format.fillColor = fills[id] }
            if let id = xf.attribute("borderId").flatMap(Int.init), borders.indices.contains(id) { format.border = borders[id] }
            if let id = xf.attribute("numFmtId").flatMap(Int.init) {
                format.numberFormat = customCodes[id] ?? ExcelNumberFormat.builtIn[id] ?? "General"
            }
            if let alignment = xf.child("alignment") {
                switch alignment.attribute("horizontal") ?? "general" {
                case "left", "fill", "justify", "distributed": format.alignment = .left
                case "center", "centerContinuous": format.alignment = .center
                case "right": format.alignment = .right
                default: break
                }
                switch alignment.attribute("vertical") ?? "bottom" {
                case "top", "justify", "distributed": format.verticalAlignment = .top
                case "center": format.verticalAlignment = .center
                default: break
                }
                format.wrapText = alignment.flag("wrapText")
                format.indent = min(alignment.attribute("indent").flatMap(Int.init) ?? 0, 15)
            }
            return format.isDefault ? nil : format
        }

        differentialStyles = (root.child("dxfs")?.children("dxf") ?? []).map { dxf in
            var style = DifferentialStyle()
            if let font = dxf.child("font") {
                if let b = font.child("b") { style.bold = on(b) }
                if let i = font.child("i") { style.italic = on(i) }
                if let u = font.child("u") { style.underline = on(u) }
                if let s = font.child("strike") { style.strikethrough = on(s) }
                style.textColor = colors.resolve(font.child("color"))
            }
            if let pattern = dxf.child("fill")?.child("patternFill") {
                style.fillColor = colors.resolve(pattern.child("bgColor")) ?? colors.resolve(pattern.child("fgColor"))
            }
            return style
        }
    }

    func format(at index: Int) -> CellFormat? {
        formats.indices.contains(index) ? formats[index] : nil
    }
}
