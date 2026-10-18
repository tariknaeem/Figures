# Changelog

Figures follows [Semantic Versioning](https://semver.org): a **major** version for changes that break
compatibility, a **minor** version for new features, and a **patch** version for fixes and speed-ups.

## 1.1.0 — 2026-10-18

Features inspired by Apple Numbers.

- **Cell controls:** checkboxes, 0–5 star ratings, pop-up menus, steppers and sliders (Insert › Controls).
  Values stay ordinary values (TRUE/FALSE, numbers, text), so formulas use them directly. Pop-up menus are
  saved as Excel dropdown lists, and Excel dropdown lists now open as pop-up menus.
- **Templates:** Personal Budget, Invoice, Checklist, Weekly Planner, Grade Book and Reading List (Insert ›
  Templates), each added as a new sheet.
- **Table Styles:** one-click colored header rows with banded rows (Home › Styles).
- **AutoFill:** drag the handle at the selection's corner to continue numbers, dates, months, weekdays and
  numbered text such as "Item 1"; Fill Right (⌘R) and Fill Series join Fill Down.
- **Summarize by Category:** groups a table by a column into a new sheet with counts, totals and averages that
  stay live (Data › Categories), like Numbers' Smart Categories.
- **Quick Calculations:** the status bar now shows Sum, Average, Min, Max and Count.
- **Duration** number format.

## 1.0.0 — 2026-10-18

First release.

- Spreadsheet app for macOS and iOS with an Excel-style ribbon (Home, Insert, Formulas, Data, View).
- Opens `.xlsx` and `.xlsm` and saves `.xlsx` and `.csv`, keeping fonts, theme colors, fills, borders,
  alignment, wrap text, Excel number formats, column widths, row heights, hidden rows and columns, merged
  cells, frozen rows, filters, conditional formatting and defined names.
- 163 functions, defined names, cross-sheet and 3D references, array constants, INDIRECT and OFFSET.
- Sorting, AutoFilter, Remove Duplicates, Find & Replace, charts, Format Painter, Paste Special, cell styles
  and conditional formatting.
- Incremental recalculation, and a grid that redraws only the rows that change.
- Grid F app icon, MIT License, security policy and privacy policy.
