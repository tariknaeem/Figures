import Foundation

/// What to suggest while a formula is being typed: function names matching the word
/// at the cursor, and the signature of the function whose arguments are being entered.
public struct FormulaAssist: Sendable {
    /// The partial function name at the end of the text, or "".
    public let prefix: String
    public let suggestions: [FunctionInfo]
    public let currentFunction: FunctionInfo?

    public init(text: String) {
        guard text.hasPrefix("=") else {
            prefix = ""
            suggestions = []
            currentFunction = nil
            return
        }
        var open: [String] = []
        var word = ""
        var inString = false
        for c in text.dropFirst() {
            if inString {
                if c == "\"" { inString = false }
                continue
            }
            if c == "\"" {
                inString = true
                word = ""
            } else if c.isLetter || c.isNumber || c == "." || c == "_" || c == "$" {
                word.append(c)
            } else {
                if c == "(" { open.append(word.uppercased()) } else if c == ")" { _ = open.popLast() }
                word = ""
            }
        }
        // Words with digits are cell references such as A1, not function names.
        let typing = !inString && word.first?.isLetter == true && !word.contains(where: \.isNumber) ? word : ""
        prefix = typing
        suggestions = typing.isEmpty ? [] : FunctionCatalog.matching(prefix: typing)
        currentFunction = open.last.flatMap { FunctionCatalog.info($0) }
    }
}
