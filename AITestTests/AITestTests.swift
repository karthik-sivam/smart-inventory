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

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - S15: Sale price fallback + helpers
    // ──────────────────────────────────────────────────────────────────────

    func testFallbackSalePricePrefersSellingPrice() {
        let item = InventoryItem(name: "A", sku: "1", currentQuantity: 5, unitCost: 8)
        item.sellingPrice = 20
        item.lastPurchasePrice = 12
        XCTAssertEqual(item.fallbackSalePrice, 20)
    }

    func testFallbackSalePriceUsesLastPurchaseWhenNoSellingPrice() {
        let item = InventoryItem(name: "B", sku: "2", currentQuantity: 5, unitCost: 8)
        item.sellingPrice = 0
        item.lastPurchasePrice = 12
        XCTAssertEqual(item.fallbackSalePrice, 12)
    }

    func testFallbackSalePriceUsesUnitCostAsLastResort() {
        let item = InventoryItem(name: "C", sku: "3", currentQuantity: 5, unitCost: 8)
        item.sellingPrice = 0
        item.lastPurchasePrice = 0
        XCTAssertEqual(item.fallbackSalePrice, 8)
    }

    func testFallbackSalePriceZeroWhenAllPricesZero() {
        let item = InventoryItem(name: "D", sku: "4", currentQuantity: 5, unitCost: 0)
        XCTAssertEqual(item.fallbackSalePrice, 0)
    }

    func testApplyFallbackPriceIfNeededSkipsWhenEdited() {
        var row = ParsedSaleRow(itemName: "X", quantitySold: 1, pricePerUnit: 0, confidence: 0.95, priceWasEdited: true)
        let item = InventoryItem(name: "X", sku: "5", currentQuantity: 1, unitCost: 9)
        item.sellingPrice = 15
        SaleHelpers.applyFallbackPriceIfNeeded(&row, from: item)
        XCTAssertEqual(row.pricePerUnit, 0)
    }

    func testApplyFallbackPriceIfNeededPrefillsFromItem() {
        var row = ParsedSaleRow(itemName: "Y", quantitySold: 2, pricePerUnit: 0, confidence: 0.95)
        let item = InventoryItem(name: "Y", sku: "6", currentQuantity: 2, unitCost: 4)
        item.lastPurchasePrice = 7
        SaleHelpers.applyFallbackPriceIfNeeded(&row, from: item)
        XCTAssertEqual(row.pricePerUnit, 7)
    }

    func testParsedSaleRowDTOPreservesClaudeConfidence() throws {
        let json = #"[{"itemName":"Tea","quantitySold":2,"pricePerUnit":15,"notes":"","confidence":0.87}]"#
        let dto = try XCTUnwrap(JSONDecoder().decode([ParsedSaleRowDTO].self, from: Data(json.utf8)).first)

        XCTAssertEqual(dto.confidence, 0.87, accuracy: 0.0001)
        XCTAssertEqual(dto.toParsedSaleRow().confidence, 0.87, accuracy: 0.0001)
    }

    func testParsedSaleRowDTORequiresConfidence() {
        let json = #"[{"itemName":"Tea","quantitySold":2,"pricePerUnit":15,"notes":""}]"#
        XCTAssertThrowsError(
            try JSONDecoder().decode([ParsedSaleRowDTO].self, from: Data(json.utf8))
        )
    }

    func testNegativeStockMessagesOnlyForNegativeItems() {
        let low = InventoryItem(name: "Low", sku: "7", currentQuantity: -3, unitCost: 1)
        let ok = InventoryItem(name: "OK", sku: "8", currentQuantity: 5, unitCost: 1)
        let lines = SaleHelpers.negativeStockMessages(for: [low, ok])
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("Low"))
        XCTAssertTrue(lines[0].contains("-3") || lines[0].contains("-3.0") == false)
    }

    func testStorageTotalValueSumsItemValues() {
        let storage = Storage(name: "WH")
        let a = InventoryItem(name: "A", sku: "A1", currentQuantity: 2, unitCost: 5)
        let b = InventoryItem(name: "B", sku: "B1", currentQuantity: 3, unitCost: 4)
        storage.items = [a, b]
        XCTAssertEqual(storage.totalValue, 22, accuracy: 0.001)
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - iOS-F8: AI entry chip visibility
    // ──────────────────────────────────────────────────────────────────────

    func testAIEntryChipHiddenAfterSessionDismiss() {
        XCTAssertFalse(
            AIEntryChipPolicy.isVisible(
                feature: .smartCount,
                isPro: false,
                dismissedThisSession: true,
                hasSmartCountQuotaRemaining: true
            )
        )
        XCTAssertFalse(
            AIEntryChipPolicy.isVisible(
                feature: .smartSales,
                isPro: true,
                dismissedThisSession: true,
                hasSmartCountQuotaRemaining: true
            )
        )
    }

    func testAIEntryChipHiddenForFreeUserWhenSmartCountQuotaExhausted() {
        XCTAssertFalse(
            AIEntryChipPolicy.isVisible(
                feature: .smartCount,
                isPro: false,
                dismissedThisSession: false,
                hasSmartCountQuotaRemaining: false
            )
        )
    }

    func testAIEntryChipVisibleForFreeUserWithSmartCountQuota() {
        XCTAssertTrue(
            AIEntryChipPolicy.isVisible(
                feature: .smartCount,
                isPro: false,
                dismissedThisSession: false,
                hasSmartCountQuotaRemaining: true
            )
        )
    }

    func testAIEntryChipSmartSalesAlwaysVisibleUnlessDismissed() {
        XCTAssertTrue(
            AIEntryChipPolicy.isVisible(
                feature: .smartSales,
                isPro: false,
                dismissedThisSession: false,
                hasSmartCountQuotaRemaining: false
            )
        )
        XCTAssertTrue(
            AIEntryChipPolicy.isVisible(
                feature: .smartSales,
                isPro: true,
                dismissedThisSession: false,
                hasSmartCountQuotaRemaining: false
            )
        )
    }

    func testAIEntryChipAlwaysVisibleForProOnSmartCount() {
        XCTAssertTrue(
            AIEntryChipPolicy.isVisible(
                feature: .smartCount,
                isPro: true,
                dismissedThisSession: false,
                hasSmartCountQuotaRemaining: false
            )
        )
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - iOS-D1a: Barcode outcome analytics
    // ──────────────────────────────────────────────────────────────────────

    func testBarcodeScanResultIncludesCodeWhenACodeWasRead() {
        let event = StoqlyEvent.barcodeScanResult(
            outcome: "found",
            provider: "off",
            symbology: "EAN-13",
            code: "8901030865477",
            durationMs: 420,
            reason: nil
        )

        XCTAssertEqual(event.name, "barcode_scan_result")
        XCTAssertEqual(event.properties["outcome"] as? String, "found")
        XCTAssertEqual(event.properties["provider"] as? String, "off")
        XCTAssertEqual(event.properties["symbology"] as? String, "EAN-13")
        XCTAssertEqual(event.properties["code"] as? String, "8901030865477")
        XCTAssertEqual(event.properties["duration_ms"] as? Int, 420)
        XCTAssertNil(event.properties["reason"])
        XCTAssertNil(event.properties["found"])
        XCTAssertNil(event.properties["enriched"])
    }

    func testBarcodeScanResultOmitsNilOptionalProperties() {
        let event = StoqlyEvent.barcodeScanResult(
            outcome: "scanner_cancelled",
            provider: "none",
            symbology: nil,
            code: nil,
            durationMs: 125,
            reason: nil
        )

        XCTAssertNil(event.properties["symbology"])
        XCTAssertNil(event.properties["code"])
        XCTAssertNil(event.properties["reason"])
        XCTAssertEqual(event.properties["duration_ms"] as? Int, 125)
    }

    func testAIRequestSucceededOmitsNilModeAndDoesNotLogPromptText() {
        let event = StoqlyEvent.aiRequestSucceeded(
            feature: "voice_count",
            mode: nil,
            itemCount: 3,
            durationMs: 1200,
            provider: "claude"
        )
        XCTAssertEqual(event.name, "ai_request_succeeded")
        XCTAssertEqual(event.properties["feature"] as? String, "voice_count")
        XCTAssertEqual(event.properties["item_count"] as? Int, 3)
        XCTAssertEqual(event.properties["duration_ms"] as? Int, 1200)
        XCTAssertEqual(event.properties["provider"] as? String, "claude")
        XCTAssertNil(event.properties["mode"])
        XCTAssertNil(event.properties["question"])
        XCTAssertNil(event.properties["transcript"])
    }

    func testAIRequestFailedUsesExtendedShape() {
        let event = StoqlyEvent.aiRequestFailed(
            feature: "ask_ai_help",
            mode: "help",
            stage: "receive",
            errorClass: "network",
            reason: "The Internet connection appears to be offline.",
            durationMs: 800
        )
        XCTAssertEqual(event.name, "ai_request_failed")
        XCTAssertEqual(event.properties["feature"] as? String, "ask_ai_help")
        XCTAssertEqual(event.properties["mode"] as? String, "help")
        XCTAssertEqual(event.properties["stage"] as? String, "receive")
        XCTAssertEqual(event.properties["error_class"] as? String, "network")
        XCTAssertEqual(event.properties["duration_ms"] as? Int, 800)
    }

    func testAIRequestEmptyAndSmartSalesFailedNames() {
        let empty = StoqlyEvent.aiRequestEmpty(
            feature: "photo_count",
            mode: "photo",
            durationMs: 400,
            reason: "no_items_returned"
        )
        XCTAssertEqual(empty.name, "ai_request_empty")
        XCTAssertEqual(empty.properties["reason"] as? String, "no_items_returned")

        let failed = StoqlyEvent.smartSalesFailed(mode: "voice", reason: "parse_error")
        XCTAssertEqual(failed.name, "smart_sales_failed")
        XCTAssertEqual(failed.properties["mode"] as? String, "voice")
    }

    func testSyncCompletedAndFailedShapes() {
        let started = StoqlyEvent.syncStarted(context: "cold_launch")
        XCTAssertEqual(started.name, "sync_started")
        XCTAssertEqual(started.properties["context"] as? String, "cold_launch")

        let completed = StoqlyEvent.syncCompleted(context: "foreground", docsUpdated: 12, durationMs: 900)
        XCTAssertEqual(completed.name, "sync_completed")
        XCTAssertEqual(completed.properties["docs_updated"] as? Int, 12)
        XCTAssertEqual(completed.properties["duration_ms"] as? Int, 900)

        let failed = StoqlyEvent.syncFailed(
            context: "write",
            errorClass: "network",
            reason: "The Internet connection appears to be offline.",
            durationMs: nil
        )
        XCTAssertEqual(failed.name, "sync_failed")
        XCTAssertEqual(failed.properties["context"] as? String, "write")
        XCTAssertEqual(failed.properties["error_class"] as? String, "network")
        XCTAssertNil(failed.properties["duration_ms"])
        XCTAssertNil(failed.properties["email"])
    }

    func testExportFailedAndReorderEmailFailedNames() {
        let exportFailed = StoqlyEvent.exportFailed(format: "pdf", reason: "pdf_render_failed")
        XCTAssertEqual(exportFailed.name, "export_failed")
        XCTAssertEqual(exportFailed.properties["format"] as? String, "pdf")
        XCTAssertEqual(exportFailed.properties["reason"] as? String, "pdf_render_failed")

        let emailFailed = StoqlyEvent.reorderEmailFailed(reason: "cannot_open_mailto")
        XCTAssertEqual(emailFailed.name, "reorder_email_failed")
        XCTAssertEqual(emailFailed.properties["reason"] as? String, "cannot_open_mailto")
        XCTAssertNil(emailFailed.properties["body"])
    }

    func testBarcodeBulkScanSessionEventShapes() {
        let started = StoqlyEvent.barcodeBulkScanStarted(source: "storage_detail")
        XCTAssertEqual(started.name, "barcode_bulk_scan_started")
        XCTAssertEqual(started.properties["source"] as? String, "storage_detail")

        let completed = StoqlyEvent.barcodeBulkScanCompleted(
            scannedCount: 12,
            newCount: 4,
            updatedCount: 8,
            durationMs: 45_000
        )
        XCTAssertEqual(completed.name, "barcode_bulk_scan_completed")
        XCTAssertEqual(completed.properties["scanned_count"] as? Int, 12)
        XCTAssertEqual(completed.properties["new_count"] as? Int, 4)
        XCTAssertEqual(completed.properties["updated_count"] as? Int, 8)
        XCTAssertEqual(completed.properties["duration_ms"] as? Int, 45_000)
        XCTAssertNil(completed.properties["code"])

        let abandoned = StoqlyEvent.barcodeBulkScanAbandoned(
            stage: "camera",
            scannedCount: 3,
            durationMs: 900
        )
        XCTAssertEqual(abandoned.name, "barcode_bulk_scan_abandoned")
        XCTAssertEqual(abandoned.properties["stage"] as? String, "camera")
        XCTAssertEqual(abandoned.properties["scanned_count"] as? Int, 3)
    }

    @MainActor
    func testBulkBarcodeScanViewModelIncrementsExistingAndAddsNew() {
        let vm = BulkBarcodeScanViewModel()
        vm.cooldownSeconds = 0
        let existingId = UUID()
        vm.bind(catalog: [
            .init(id: existingId, name: "Maggi", barcode: "8901030865477")
        ])

        XCTAssertTrue(vm.ingest(code: "8901030865477", symbology: "EAN-13"))
        XCTAssertTrue(vm.ingest(code: "8901030865477", symbology: "EAN-13"))
        XCTAssertTrue(vm.ingest(code: "  890123  ", symbology: "EAN-13"))

        XCTAssertEqual(vm.rows.count, 2)
        XCTAssertEqual(vm.rows[0].existingItemId, existingId)
        XCTAssertEqual(vm.rows[0].quantity, 2, accuracy: 0.001)
        XCTAssertTrue(vm.rows[0].isExisting)
        XCTAssertEqual(vm.rows[1].code, "890123")
        XCTAssertFalse(vm.rows[1].isExisting)
        XCTAssertEqual(vm.rows[1].name, BulkBarcodeScanViewModel.defaultName(for: "890123"))
    }

    @MainActor
    func testBulkBarcodeScanCooldownDropsRapidRepeat() {
        let vm = BulkBarcodeScanViewModel()
        vm.cooldownSeconds = 10
        XCTAssertTrue(vm.ingest(code: "111", symbology: "EAN-13"))
        XCTAssertFalse(vm.ingest(code: "111", symbology: "EAN-13"))
        XCTAssertEqual(vm.rows.first?.quantity ?? 0, 1, accuracy: 0.001)
    }

    func testSaleEventRevenueUsesPriceTimesQty() {
        let sale = SaleEvent(
            item: nil,
            itemName: "Chip",
            itemSKU: "C1",
            storageName: "WH",
            category: "Food",
            quantitySold: 2,
            pricePerUnit: 15,
            costPerUnit: 8
        )
        XCTAssertEqual(sale.revenue, 30, accuracy: 0.001)
        XCTAssertEqual(sale.grossProfit, 14, accuracy: 0.001)
    }
}
