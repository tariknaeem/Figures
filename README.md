# Figures

A spreadsheet app for macOS and iOS that opens and saves Excel workbooks (`.xlsx`, and `.xlsm` read-only).
One Swift engine (`SheetCore`) and one SwiftUI interface (`SheetUI`) serve both platforms.

## Build

| Target | Requirement | Command |
|---|---|---|
| Mac app | Command Line Tools | `./scripts/build-mac-app.sh`, then `open build/Figures.app` |
| iPhone / iPad app | Full Xcode | `cd Apple && xcodegen && open Figures.xcodeproj`, choose **Figures-iOS**, set your team, Run |
| Engine checks | Command Line Tools | `swift run SheetCoreChecks` |
| Inspect any workbook | Command Line Tools | `swift run SheetCoreChecks file.xlsx` (set `FIGURES_VERBOSE=1` to list failing formulas) |
| Sample workbook | Command Line Tools | `swift run SheetCoreChecks --tour Samples/Tour.xlsx` |

## Opening Excel files

Figures reads what most workbooks use: values, formulas (including shared formulas and defined names), the
workbook theme (theme colors with tints, legacy indexed colors), the default font, per-cell fonts, sizes,
colors, fills, borders with styles and colors, alignment, wrap text, indent, Excel number format codes
(sections, colors, conditions, dates, times, fractions, scientific, accounting), column widths, row heights,
hidden rows and columns, merged cells, frozen rows, gridlines, AutoFilter, and conditional formatting
(cell value, text, duplicates, top/bottom, above/below average, formula rules, color scales, data bars).

Checked against Apache POI's 356 test workbooks: 333 open. The rest are intentionally corrupt fuzzing
files, XML-bomb tests and two encrypted or Excel 97–2003 files, which get a clear message instead.

Not read: charts, images, shapes, comments, pivot tables, tables' structured references (`Table1[Amount]`),
data validation, icon sets, rich text within a cell (the text is kept, its mixed formatting is not),
external workbook links, and macros (`.xlsm` opens, saves as `.xlsx`).

## Ribbon

| Tab | Groups |
|---|---|
| Home | Clipboard (paste, cut, copy, Format Painter, Paste Special, undo, redo) · Font (family, size, bold, italic, underline, strikethrough, borders, fill and font colors) · Alignment (top/middle/bottom, left/center/right, wrap, indent, merge) · Number (presets with previews, custom codes, accounting, percent, comma, decimals) · Styles (conditional formatting, cell styles) · Cells (insert, delete, format, hide/unhide, autofit) · Editing (AutoSum, Fill Down, Clear, Sort & Filter, Find) |
| Insert | Rows, columns, sheets · Column, bar, line and pie charts · Today and Now · Functions by category |
| Formulas | AutoSum · Function library by category · Defined names · Show Formulas |
| Data | Sort · Filter · Clear filter · Remove Duplicates · Find & Replace |
| View | Gridlines · Show Formulas · Zoom · Freeze panes |

Also: filter dropdowns, right-click menus on cells and headers, column and row resizing, a Name Box that jumps
to cells or names, formula autocomplete with argument hints, text that overflows into empty neighbors, and a
status bar with Sum/Average/Count and zoom.

Shortcuts: ⌘B ⌘I ⌘U · ⌘D fill down · ⌘F find · ⌘1 format cells · ⌘; date · ⇧⌘; time · ⇧⌘L filter ·
⌃⇧4 currency · ⌃⇧5 percent · ⌘= / ⌘− zoom · Esc cancels editing or Format Painter.

## Formulas

About 160 functions (see `Sources/SheetCore/FunctionCatalog.swift`), Excel precedence and coercion, defined
names, cross-sheet and 3D references (`Jan:Mar!B2`), whole rows and columns, array constants, empty arguments,
INDIRECT and OFFSET. Inserting or deleting rows and columns updates references on every sheet.

## Not yet supported

Saved charts (charts are previews), dynamic array formulas, structured table references, data validation,
comments, frozen columns, printing, and sheet renames updating formulas that refer to the old name.

## Privacy

Figures works entirely on your device. It collects no data, has no analytics and makes no network requests.

## License

The source code is available under the [MIT License](LICENSE). Copyright © 2026 Tarik Naeem.
Contributions are accepted under the same license.

The **Figures** name and the Grid F app icon identify this project and are not licensed under the MIT
License. Forks and other distributions must use a different name and icon.

Figures is an independent project. It is not affiliated with, endorsed by or sponsored by Microsoft
Corporation. Microsoft and Excel are trademarks of the Microsoft group of companies; they are mentioned
only to describe file compatibility.

Security problems: see [SECURITY.md](SECURITY.md).
