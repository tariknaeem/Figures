import SheetCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Excel workbook (.xlsx); declared by the system on macOS and iOS.
    public static let excelWorkbook = UTType(importedAs: "org.openxmlformats.spreadsheetml.sheet")
    /// Macro-enabled Excel workbook (.xlsm).
    public static let excelMacroWorkbook = UTType(importedAs: "org.openxmlformats.spreadsheetml.sheet.macroenabled")
}

/// A workbook stored as .xlsx, or as .csv for the first sheet. Macro-enabled .xlsm files open,
/// but save as .xlsx because their macros are not kept.
public struct WorkbookDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.excelWorkbook, .excelMacroWorkbook, .commaSeparatedText] }
    public static var writableContentTypes: [UTType] { [.excelWorkbook, .commaSeparatedText] }

    public var workbook: Workbook

    public init(workbook: Workbook = Workbook()) {
        self.workbook = workbook
    }

    public init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if configuration.contentType.conforms(to: .commaSeparatedText) {
            workbook = Workbook(sheets: [CSV.sheet(from: String(decoding: data, as: UTF8.self), named: "Sheet1")])
        } else {
            workbook = try XLSXReader.workbook(from: data)
        }
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = configuration.contentType.conforms(to: .commaSeparatedText)
            ? CSV.data(for: workbook, sheet: 0)
            : XLSXWriter.data(for: workbook)
        return FileWrapper(regularFileWithContents: data)
    }
}
