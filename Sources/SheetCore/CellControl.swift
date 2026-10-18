import Foundation

/// Where a pop-up menu's choices come from.
public enum PopUpSource: Hashable, Sendable {
    case items([String])
    /// A reference such as `$F$1:$F$5` or `Lists!$A$1:$A$9`, without `=`.
    case range(String)
}

/// An interactive control drawn in a cell, as in Numbers. The cell's value stays an ordinary value:
/// TRUE/FALSE for checkboxes, 0–5 for ratings, the chosen text for pop-up menus and a number for steppers and sliders.
public enum CellControl: Hashable, Sendable {
    case checkbox
    case rating
    case popUp(PopUpSource)
    case stepper(minimum: Double, maximum: Double, step: Double)
    case slider(minimum: Double, maximum: Double, step: Double)

    /// Input that sets the control to a value, kept within the control's limits.
    public func input(for value: CellValue) -> String {
        switch self {
        case .checkbox:
            return (try? Calculator.boolean(value)) == true ? "TRUE" : "FALSE"
        case .rating:
            let stars = ((try? Calculator.number(value)) ?? 0).rounded()
            return CellInput.rawInput(for: .number(min(5, max(0, stars))))
        case .stepper(let low, let high, _), .slider(let low, let high, _):
            let number = (try? Calculator.number(value)) ?? low
            return CellInput.rawInput(for: .number(min(high, max(low, number))))
        case .popUp:
            return value == .empty ? "" : CellInput.rawInput(for: .text(value.displayText))
        }
    }
}

extension Calculator {
    /// The choices of a pop-up menu, reading referenced cells when the menu uses a range.
    public func popUpOptions(_ source: PopUpSource, sheet: Int) -> [String] {
        switch source {
        case .items(let items):
            return items
        case .range(let reference):
            guard case .success(let expr) = formula("=" + reference),
                  case .range(let target, let range) = evaluate(expr, sheet) else { return [] }
            var seen = Set<String>()
            return cells(in: range, sheet: target).compactMap { address, _ in
                let text = displayText(sheet: target, at: address)
                return seen.insert(text).inserted ? text : nil
            }
        }
    }
}

extension CellValue {
    /// The value as a number, the way arithmetic reads it; nil for text that is not a number and for errors.
    public var numberValue: Double? { try? Calculator.number(self) }

    /// Whether the value counts as TRUE, as IF and checkboxes read it.
    public var isTrue: Bool { (try? Calculator.boolean(self)) == true }
}
