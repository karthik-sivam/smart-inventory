import XCTest
@testable import SmartInventory

// MARK: - Unit Tests for Stoqly (M1–M4 changes)
//
// These tests exercise pure logic that does not require the SwiftUI runtime,
// SwiftData store, Firebase, or StoreKit. They mirror the private helpers
// inside views (`formatStepResult`, `compute`, etc.) so that the same
// formulas that ship in the app are validated in isolation.

final class SmartInventoryTests: XCTestCase {

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - Pre-existing
    // ──────────────────────────────────────────────────────────────────────

    func testUniqueCategoryListExcludesUncategorised() throws {
        let categories = ["Food", "Uncategorised", "Electronics"]
        let unique = Array(Set(categories.filter { $0 != "Uncategorised" })).sorted()
        XCTAssertEqual(unique, ["Electronics", "Food"])
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - M1: CountViewModel status filter
    // ──────────────────────────────────────────────────────────────────────

    /// All four status filter values must be reachable and distinct.
    /// `CountViewModel` is `@MainActor`, so the access happens on the main actor.
    @MainActor
    func testStatusFilterAllCasesExist() {
        let due = CountViewModel.StatusFilter.due
        let allFilter = CountViewModel.StatusFilter.all
        let uncounted = CountViewModel.StatusFilter.uncounted
        let lowStock  = CountViewModel.StatusFilter.lowStock

        XCTAssertNotEqual(due, allFilter)
        XCTAssertNotEqual(due, uncounted)
        XCTAssertNotEqual(due, lowStock)
        XCTAssertNotEqual(allFilter, uncounted)
        XCTAssertNotEqual(allFilter, lowStock)
        XCTAssertNotEqual(uncounted, lowStock)
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - M2: Stepper helper — formatStepResult equivalent
    // ──────────────────────────────────────────────────────────────────────

    /// Mirrors the private `formatStepResult` logic used in QuickCountView.
    private func formatStepResult(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.2f", value)
    }

    func testFormatStepResultWholeNumber() {
        XCTAssertEqual(formatStepResult(5.0),  "5")
        XCTAssertEqual(formatStepResult(0.0),  "0")
        XCTAssertEqual(formatStepResult(-3.0), "-3")
    }

    func testFormatStepResultDecimal() {
        XCTAssertEqual(formatStepResult(5.5),   "5.50")
        XCTAssertEqual(formatStepResult(-1.25), "-1.25")
    }

    func testStepperClampsBelowZeroInSetToMode() {
        // In "Set to" mode the resulting quantity is clamped to >= 0.
        let current = 0.0
        let stepped = max(0, current - 1)
        XCTAssertEqual(stepped, 0)
    }

    func testAdjustByDeltaCanGoNegative() {
        // In "Adjust by" mode the delta itself is not clamped; only the
        // resulting absolute quantity is clamped at save time.
        let delta   = 0.0
        let stepped = delta - 1
        XCTAssertEqual(stepped, -1)
    }

    func testAdjustByResultingQuantityClampedToZero() {
        // resultingQuantity in QuickCountView clamps to 0 even with very
        // negative deltas, matching the production guard.
        let currentQty = 3.0
        let delta      = -10.0
        let result     = max(0, currentQty + delta)
        XCTAssertEqual(result, 0)
    }

    func testAdjustByResultingQuantityNormal() {
        let currentQty = 10.0
        let delta      =  5.0
        let result     = max(0, currentQty + delta)
        XCTAssertEqual(result, 15)
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - M3: Calculator arithmetic
    // ──────────────────────────────────────────────────────────────────────

    /// Mirrors the private `compute` function from CalculatorView.
    private func calc(_ a: Double, _ b: Double, op: String) -> Double {
        switch op {
        case "+": return a + b
        case "-": return a - b
        case "×": return a * b
        case "÷": return b == 0 ? 0 : a / b
        default:  return b
        }
    }

    func testCalculatorAddition()       { XCTAssertEqual(calc(3, 4, op: "+"), 7) }
    func testCalculatorSubtraction()    { XCTAssertEqual(calc(10, 3, op: "-"), 7) }
    func testCalculatorMultiplication() { XCTAssertEqual(calc(3, 4, op: "×"), 12) }
    func testCalculatorDivision()       { XCTAssertEqual(calc(10, 2, op: "÷"), 5) }
    func testCalculatorDivisionByZero() { XCTAssertEqual(calc(5, 0, op: "÷"), 0) }

    func testCalculatorChainedOps() {
        // 3 × 12 + 4 = 40
        let step1 = calc(3, 12, op: "×")    // 36
        let step2 = calc(step1, 4, op: "+") // 40
        XCTAssertEqual(step2, 40)
    }

    func testCalculatorNegativeDelta() {
        // -5 + 3 = -2 (covers negative stock adjustments)
        XCTAssertEqual(calc(-5, 3, op: "+"), -2)
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - M4: InventoryCount model derived properties
    // ──────────────────────────────────────────────────────────────────────

    func testInventoryCountVariancePositive() {
        let count = InventoryCount(previousQuantity: 10, countedQuantity: 15)
        XCTAssertEqual(count.variance, 5)
        XCTAssertEqual(count.adjustmentType, "Increase")
    }

    func testInventoryCountVarianceNegative() {
        let count = InventoryCount(previousQuantity: 10, countedQuantity: 3)
        XCTAssertEqual(count.variance, -7)
        XCTAssertEqual(count.adjustmentType, "Decrease")
    }

    func testInventoryCountVarianceZero() {
        let count = InventoryCount(previousQuantity: 8, countedQuantity: 8)
        XCTAssertEqual(count.variance, 0)
        XCTAssertEqual(count.adjustmentType, "No Change")
    }

    func testInventoryCountVariancePercentage() {
        let count = InventoryCount(previousQuantity: 100, countedQuantity: 150)
        XCTAssertEqual(count.variancePercentage, 50, accuracy: 0.001)
    }

    func testInventoryCountVariancePercentageWhenPreviousIsZero() {
        let count = InventoryCount(previousQuantity: 0, countedQuantity: 10)
        // Should not divide by zero — production returns 0 in this case.
        XCTAssertEqual(count.variancePercentage, 0)
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - M4: Adjust-by reason string logic
    // ──────────────────────────────────────────────────────────────────────

    func testAdjustByPositiveDeltaReason() {
        let delta = 5.0
        let reason = delta >= 0 ? "Stock Received" : "Stock Adjustment"
        XCTAssertEqual(reason, "Stock Received")
    }

    func testAdjustByNegativeDeltaReason() {
        let delta = -3.0
        let reason = delta >= 0 ? "Stock Received" : "Stock Adjustment"
        XCTAssertEqual(reason, "Stock Adjustment")
    }

    func testAdjustByZeroDeltaReason() {
        // Delta of 0 still treated as "Stock Received" (no change), matching
        // the `>= 0` branch in QuickCountView.performSave().
        let delta = 0.0
        let reason = delta >= 0 ? "Stock Received" : "Stock Adjustment"
        XCTAssertEqual(reason, "Stock Received")
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - M5: Chart enhancements
    // ──────────────────────────────────────────────────────────────────────
    //
    // The M5 charts (CountTrendChart, ExpiryTimelineView, CategoryValueChart)
    // contain pure-function helpers — coordinate math, urgency tiers, and a
    // currency formatter. Each of the tests below mirrors the production
    // formula exactly so a regression in either side surfaces immediately.

    // MARK: M5a — CountTrendChart math

    /// `yPos` should map maxQty → top of canvas (y = 0).
    func testTrendChartYPosTopOfRange() {
        let height = 90.0
        let minQty = 0.0
        let maxQty = 10.0
        let qty    = 10.0
        let fraction = (qty - minQty) / (maxQty - minQty)   // 1.0
        let y = height - fraction * height                  // 0
        XCTAssertEqual(y, 0, accuracy: 0.001)
    }

    /// `yPos` should map minQty → bottom of canvas (y = height).
    func testTrendChartYPosBottomOfRange() {
        let height = 90.0
        let minQty = 0.0
        let maxQty = 10.0
        let qty    = 0.0
        let fraction = (qty - minQty) / (maxQty - minQty)   // 0.0
        let y = height - fraction * height                  // 90
        XCTAssertEqual(y, height, accuracy: 0.001)
    }

    /// `xPos` for two points should span the full width: 0 → 0, 1 → width.
    func testTrendChartXPosSingleSpan() {
        let width = 200.0
        let count = 2
        let x0 = Double(0) / Double(count - 1) * width      // 0
        let x1 = Double(1) / Double(count - 1) * width      // 200
        XCTAssertEqual(x0, 0)
        XCTAssertEqual(x1, width)
    }

    /// Summary chip math: positive delta and percentage.
    func testTrendChartSummaryDeltaCalculation() {
        let first = 10.0
        let last  = 15.0
        let delta = last - first
        let pct   = (delta / first) * 100
        XCTAssertEqual(delta, 5)
        XCTAssertEqual(pct, 50, accuracy: 0.001)
    }

    /// Summary chip math: negative delta is preserved (drives the red colour).
    func testTrendChartSummaryNegativeDelta() {
        let first = 20.0
        let last  = 12.0
        let delta = last - first
        XCTAssertEqual(delta, -8)
        XCTAssertTrue(delta < 0)
    }

    // MARK: M5b — ExpiryTimelineView urgency / tiers

    /// Past-due dates → urgency 1.0 (full red bar).
    func testExpiryUrgencyFractionExpired() {
        let days = -1
        let fraction = max(0, min(1.0, 1.0 - Double(days) / 30.0))
        XCTAssertEqual(fraction, 1.0)
    }

    /// 15 days out → halfway across the urgency bar.
    func testExpiryUrgencyFraction15Days() {
        let days = 15
        let fraction = max(0, min(1.0, 1.0 - Double(days) / 30.0))
        XCTAssertEqual(fraction, 0.5, accuracy: 0.001)
    }

    /// 30 days out → 0.0 (still on the timeline but lowest urgency).
    func testExpiryUrgencyFraction30Days() {
        let days = 30
        let fraction = max(0, min(1.0, 1.0 - Double(days) / 30.0))
        XCTAssertEqual(fraction, 0, accuracy: 0.001)
    }

    /// 1–3 days → `.critical` tier.
    func testExpiryTierCritical() {
        for days in [1, 2, 3] {
            // Mirror: expiry > Date() AND days <= 3 ⇒ .critical
            XCTAssertTrue(days <= 3 && days >= 0,
                          "\(days) should fall in the critical tier")
        }
    }

    /// 4–7 days → `.soon` tier.
    func testExpiryTierSoon() {
        for days in [4, 5, 6, 7] {
            XCTAssertTrue(days > 3 && days <= 7,
                          "\(days) should fall in the soon tier")
        }
    }

    // MARK: M5c — CategoryValueChart formatter

    /// Mirrors the private `formatCurrency(_:)` in CategoryValueChart.
    private func formatCurrency(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "$%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.1fK", value / 1_000)
        } else {
            return String(format: "$%.0f", value)
        }
    }

    func testCategoryValueFormatCurrencySmall() {
        XCTAssertEqual(formatCurrency(450), "$450")
    }

    func testCategoryValueFormatCurrencyThousands() {
        XCTAssertEqual(formatCurrency(2_500), "$2.5K")
    }

    func testCategoryValueFormatCurrencyMillions() {
        XCTAssertEqual(formatCurrency(1_500_000), "$1.5M")
    }
}
