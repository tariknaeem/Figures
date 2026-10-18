import AppKit
import SheetCore
import SheetUI
import SwiftUI

// Renders the Figures window to a PNG so the interface can be reviewed without a screen.
// Usage: swift run FiguresSnapshot workbook.xlsx out.png [width] [height]
let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("Usage: FiguresSnapshot workbook.xlsx out.png [width] [height]")
    exit(1)
}
var workbook = (try? XLSXReader.workbook(from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))) ?? Workbook()
// FIGURES_DEMO=1 adds sample canvas objects to the first sheet.
if ProcessInfo.processInfo.environment["FIGURES_DEMO"] != nil, !workbook.sheets.isEmpty {
    workbook.sheets[0].canvas = [
        CanvasObject(x: 520, y: 60, width: 420, height: 250,
                     kind: .chart(.column, range: CellRange(CellAddress(row: 3, column: 0), CellAddress(row: 11, column: 2)), title: "Budget vs Actual")),
        CanvasObject(x: 520, y: 330, width: 260, height: 64, kind: .text("Groceries and entertainment ran over budget this month."),
                     fill: RGBColor(hex: "FFF6D5"), fontSize: 13),
        CanvasObject(x: 800, y: 330, width: 140, height: 64, kind: .shape(.roundedRectangle), fill: RGBColor(hex: "4CC38A")),
    ]
}
let width = arguments.count > 3 ? Double(arguments[3]) ?? 1400 : 1400
let height = arguments.count > 4 ? Double(arguments[4]) ?? 900 : 900

@MainActor
func render() {
    let view = WorkbookView(workbook: .constant(workbook))
        .frame(width: width, height: height)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, ProcessInfo.processInfo.environment["FIGURES_DARK"] != nil ? .dark : .light)
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
    let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    if ProcessInfo.processInfo.environment["FIGURES_DARK"] != nil { window.appearance = NSAppearance(named: .darkAqua) }
    window.contentView = hosting
    hosting.layoutSubtreeIfNeeded()
    // Let SwiftUI lay out lazy content before capturing.
    RunLoop.main.run(until: Date().addingTimeInterval(1.0))
    hosting.layoutSubtreeIfNeeded()
    guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { exit(1) }
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
    try? png.write(to: URL(fileURLWithPath: arguments[2]))
    print("Wrote \(arguments[2])")
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    render()
}
