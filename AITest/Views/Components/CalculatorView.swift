import SwiftUI

// MARK: - Calculator View
//
// A standard 4-function calculator presented as a sheet.
// `onUse` is called with the current display value when the user taps "Use".

struct CalculatorView: View {

    /// Called when the user taps "Use Result" — receives the numeric result.
    var onUse: (Double) -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var displayText: String = "0"
    @State private var storedValue: Double = 0
    @State private var pendingOp: CalcOp? = nil
    @State private var didJustEqualise: Bool = false   // tracks post-= state
    @State private var expression: String = ""          // top line "12 × 3"

    // MARK: - Button model

    enum CalcOp { case add, subtract, multiply, divide }

    enum CalcButton: Hashable {
        case digit(Int)
        case decimal
        case op(CalcOp)
        case equals
        case clear
        case toggleSign
        case percent
        case use

        var label: String {
            switch self {
            case .digit(let n):  return "\(n)"
            case .decimal:       return "."
            case .op(let o):
                switch o {
                case .add:       return "+"
                case .subtract:  return "−"
                case .multiply:  return "×"
                case .divide:    return "÷"
                }
            case .equals:        return "="
            case .clear:         return "C"
            case .toggleSign:    return "+/−"
            case .percent:       return "%"
            case .use:           return "Use"
            }
        }

        var foregroundColor: Color {
            switch self {
            case .use:            return .white
            case .op, .equals:    return .white
            case .clear, .toggleSign, .percent: return .primary
            default:              return .primary
            }
        }

        var backgroundColor: Color {
            switch self {
            case .use:            return .blue
            case .equals:         return .orange
            case .op:             return .orange
            case .clear, .toggleSign, .percent: return Color(.systemGray4)
            default:              return Color(.systemGray5)
            }
        }
    }

    // Button grid: rows of 4
    private let buttonRows: [[CalcButton]] = [
        [.clear,       .toggleSign, .percent,          .op(.divide)],
        [.digit(7),   .digit(8),   .digit(9),          .op(.multiply)],
        [.digit(4),   .digit(5),   .digit(6),          .op(.subtract)],
        [.digit(1),   .digit(2),   .digit(3),          .op(.add)],
        [.digit(0),   .decimal,    .equals,             .use],
    ]

    // MARK: - Derived

    private var displayValue: Double { Double(displayText) ?? 0 }

    private var formattedDisplay: String {
        let d = Double(displayText) ?? 0
        // Show decimal point in-progress (user typed "3.")
        let hasTrailingDot = displayText.hasSuffix(".")
        if hasTrailingDot { return displayText }
        // Preserve trailing zeros the user typed after decimal (e.g. "3.10")
        if displayText.contains(".") { return displayText }
        // Integer — no decimals needed
        if d == d.rounded() && !displayText.contains(".") {
            return String(format: "%.0f", d)
        }
        return displayText
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Display ────────────────────────────────────────────
                VStack(alignment: .trailing, spacing: 4) {
                    // Expression line
                    Text(expression)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    // Main number
                    Text(formattedDisplay)
                        .font(.system(size: 56, weight: .light, design: .rounded))
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .background(Color(.systemGroupedBackground))

                Divider()

                // ── Button grid ───────────────────────────────────────
                VStack(spacing: 12) {
                    ForEach(buttonRows, id: \.self) { row in
                        HStack(spacing: 12) {
                            ForEach(row, id: \.self) { btn in
                                CalcButtonView(button: btn) {
                                    handleTap(btn)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Button handler

    private func handleTap(_ btn: CalcButton) {
        switch btn {

        case .digit(let n):
            if displayText == "0" || didJustEqualise {
                displayText = "\(n)"
                didJustEqualise = false
            } else {
                // Cap at 12 digits to avoid overflow display
                if displayText.replacingOccurrences(of: ".", with: "")
                              .replacingOccurrences(of: "-", with: "").count < 12 {
                    displayText += "\(n)"
                }
            }

        case .decimal:
            if didJustEqualise { displayText = "0"; didJustEqualise = false }
            if !displayText.contains(".") { displayText += "." }

        case .clear:
            displayText     = "0"
            storedValue     = 0
            pendingOp       = nil
            expression      = ""
            didJustEqualise = false

        case .toggleSign:
            if let d = Double(displayText) {
                let toggled = -d
                displayText = toggled.truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0f", toggled)
                    : "\(toggled)"
            }

        case .percent:
            if let d = Double(displayText) {
                let pct = d / 100
                displayText = pct.truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0f", pct)
                    : "\(pct)"
            }

        case .op(let op):
            // If there's already a pending op, resolve it first
            if let existing = pendingOp, !didJustEqualise {
                let result = compute(storedValue, displayValue, op: existing)
                displayText = formatResult(result)
                storedValue = result
            } else {
                storedValue = displayValue
            }
            pendingOp       = op
            expression      = "\(formattedDisplay) \(btn.label)"
            didJustEqualise = true   // next digit press replaces display

        case .equals:
            guard let op = pendingOp else { return }
            let result  = compute(storedValue, displayValue, op: op)
            expression  = "\(expression) \(formattedDisplay) ="
            displayText = formatResult(result)
            storedValue = result
            pendingOp   = nil
            didJustEqualise = true

        case .use:
            let result = pendingOp != nil
                ? compute(storedValue, displayValue, op: pendingOp!)
                : displayValue
            onUse(result)
            dismiss()
        }
    }

    // MARK: - Math

    private func compute(_ a: Double, _ b: Double, op: CalcOp) -> Double {
        switch op {
        case .add:      return a + b
        case .subtract: return a - b
        case .multiply: return a * b
        case .divide:   return b == 0 ? 0 : a / b
        }
    }

    private func formatResult(_ value: Double) -> String {
        if value.isNaN || value.isInfinite { return "Error" }
        return value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.4f", value)
                .trimmingCharacters(in: CharacterSet(charactersIn: "0"))
                // ensure we don't trim the decimal point itself
                .replacingOccurrences(of: #"^\."#, with: "0.", options: .regularExpression)
    }
}

// MARK: - Individual button view

private struct CalcButtonView: View {
    let button: CalculatorView.CalcButton
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(button.label)
                .font(button == .use
                      ? .headline
                      : .title2.weight(.medium))
                .foregroundColor(button.foregroundColor)
                .frame(maxWidth: .infinity, minHeight: 70)
                .background(button.backgroundColor)
                .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}
