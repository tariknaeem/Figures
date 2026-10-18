import SheetUI
import SwiftUI

@main
struct FiguresApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: WorkbookDocument()) { file in
            WorkbookView(workbook: file.$document.workbook)
                #if os(macOS)
                .frame(minWidth: 720, minHeight: 480)
                #endif
        }
    }
}
