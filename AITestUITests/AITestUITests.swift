import XCTest

// MARK: - UI Tests for Stoqly (M1–M4 changes)
//
// These tests assume the app launches into an authenticated state with at
// least one Storage and at least one InventoryItem already seeded. When the
// app is on the Auth screen (no signed-in session), every test calls
// XCTSkip so the suite degrades gracefully instead of producing red noise.
//
// Stoqly uses a custom tab bar (not UITabBar), so we navigate by tapping
// `app.buttons["Audit"]` / `app.buttons["Items"]` rather than indexing into
// `app.tabBars.buttons`.
//
// Note: setUp / tearDown are intentionally non-isolated (Swift 6 strict
// concurrency rejects an `@MainActor` override of a `nonisolated` parent
// method). Per-test launch happens inside the `@MainActor` test body via
// `launchedApp()`.

final class SmartInventoryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - Per-test launch
    // ──────────────────────────────────────────────────────────────────────

    /// Launches the app and dismisses the onboarding sheet if it is shown.
    /// NOTE: do not pass `-UITestResetOnboarding` — that flag *forces*
    /// onboarding ON for every launch (used by Maestro), which is the
    /// opposite of what we want for XCUITest.
    @MainActor
    private func launchedApp() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        try dismissOnboardingIfPresent(app)
        return app
    }

    /// On a fresh install Onboarding shows before AuthView. Tap "Skip" if
    /// shown; otherwise step through "Get Started".
    @MainActor
    private func dismissOnboardingIfPresent(_ app: XCUIApplication) throws {
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 2) {
            skip.tap()
            return
        }
        let getStarted = app.buttons["Get Started"]
        if getStarted.exists { getStarted.tap() }
    }

    /// Tests that need a signed-in session call this. If the app is on the
    /// AuthView (Sign In / Sign Up), we skip rather than fail, since UI
    /// tests cannot fully exercise Firebase + Google Sign-In.
    @MainActor
    private func requireSignedInSession(_ app: XCUIApplication) throws {
        let signInBtn = app.buttons["Sign In"]
        let signUpBtn = app.buttons["Sign Up"]
        if signInBtn.waitForExistence(timeout: 2) || signUpBtn.exists {
            throw XCTSkip("App is on Auth screen — UI tests require an authenticated session.")
        }

        // Confirm the authenticated app shell is visible by waiting for any
        // tab bar button.
        let dashboardTab = app.buttons["Dashboard"]
        if !dashboardTab.waitForExistence(timeout: 5) {
            throw XCTSkip("Authenticated app shell did not appear — skipping UI tests.")
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - Tab navigation helpers (custom tab bar)
    // ──────────────────────────────────────────────────────────────────────

    @MainActor
    private func openAuditTab(_ app: XCUIApplication) throws {
        try requireSignedInSession(app)
        let auditBtn = app.buttons["Audit"]
        XCTAssertTrue(auditBtn.waitForExistence(timeout: 5),
                      "Audit tab button should exist in the custom tab bar")
        auditBtn.tap()
    }

    @MainActor
    private func openItemsTab(_ app: XCUIApplication) throws {
        try requireSignedInSession(app)
        let itemsBtn = app.buttons["Items"]
        XCTAssertTrue(itemsBtn.waitForExistence(timeout: 5),
                      "Items tab button should exist in the custom tab bar")
        itemsBtn.tap()
    }

    @MainActor
    private func openDashboardTab(_ app: XCUIApplication) throws {
        try requireSignedInSession(app)
        let dashBtn = app.buttons["Dashboard"]
        XCTAssertTrue(dashBtn.waitForExistence(timeout: 5),
                      "Dashboard tab button should exist in the custom tab bar")
        dashBtn.tap()
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - Item card / row finders
    // ──────────────────────────────────────────────────────────────────────

    /// Audit tab: each item card is a SwiftUI `Button` whose accessibility
    /// label includes the per-item "last counted" string ("Counted today",
    /// "Counted N days ago", "Counted yesterday", or "Never counted").
    /// Filter chips and tab buttons never include those substrings, so the
    /// predicate is unambiguous.
    @MainActor
    private func firstAuditCard(_ app: XCUIApplication, timeout: TimeInterval = 5) -> XCUIElement {
        let predicate = NSPredicate(format:
            "label CONTAINS 'Counted today' OR " +
            "label CONTAINS 'Counted yesterday' OR " +
            "label CONTAINS 'days ago' OR " +
            "label CONTAINS 'Never counted'")
        let card = app.buttons.matching(predicate).firstMatch
        _ = card.waitForExistence(timeout: timeout)
        return card
    }

    /// Items tab: each row is rendered inside a `List`. Match by the
    /// "SKU:" substring that always appears in the row label.
    @MainActor
    private func firstItemRow(_ app: XCUIApplication, timeout: TimeInterval = 5) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS 'SKU:'")

        // Try cells (UITableView-backed lists).
        let cell = app.cells.matching(predicate).firstMatch
        if cell.waitForExistence(timeout: timeout) { return cell }

        // Fall back to buttons (NavigationLink rows on some iOS versions).
        let button = app.buttons.matching(predicate).firstMatch
        _ = button.waitForExistence(timeout: 1)
        return button
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - M1: Audit (Count) tab
    // ──────────────────────────────────────────────────────────────────────

    /// Audit tab must be reachable and show the "N of M counted" progress label.
    @MainActor
    func testAuditTabLoads() throws {
        let app = try launchedApp()
        try openAuditTab(app)

        // Header is `\(counted) of \(filtered) counted` → match "of " + "counted".
        let progressLabel = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'of' AND label CONTAINS 'counted'")
        ).firstMatch

        XCTAssertTrue(progressLabel.waitForExistence(timeout: 5),
                      "Expected a progress label like 'N of M counted'")
    }

    /// Filter chips — Due / Uncounted / Low Stock / All — must all be visible.
    @MainActor
    func testAuditFilterChipsExist() throws {
        let app = try launchedApp()
        try openAuditTab(app)

        XCTAssertTrue(app.buttons["Due"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Uncounted"].exists)
        XCTAssertTrue(app.buttons["Low Stock"].exists)
        XCTAssertTrue(app.buttons["All"].exists)
    }

    /// Tapping a filter chip changes selection without crashing.
    @MainActor
    func testAuditFilterChipTap() throws {
        let app = try launchedApp()
        try openAuditTab(app)

        let dueChip = app.buttons["Due"]
        XCTAssertTrue(dueChip.waitForExistence(timeout: 5))
        dueChip.tap()

        let uncountedChip = app.buttons["Uncounted"]
        XCTAssertTrue(uncountedChip.exists)
        uncountedChip.tap()

        // Tap "All" status filter — the button label is just "All".
        app.buttons["All"].firstMatch.tap()
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - M2: QuickCountView — mode toggle + stepper
    // ──────────────────────────────────────────────────────────────────────

    /// Opening QuickCountView from the Audit tab shows Set to / Adjust by picker.
    @MainActor
    func testQuickCountViewModePicker() throws {
        let app = try launchedApp()
        try openAuditTab(app)

        let card = firstAuditCard(app)
        guard card.exists else {
            throw XCTSkip("No audit items — seed at least one InventoryItem.")
        }
        card.tap()

        XCTAssertTrue(app.buttons["Set to"].waitForExistence(timeout: 5),
                      "QuickCountView should show 'Set to' segment")
        XCTAssertTrue(app.buttons["Adjust by"].exists,
                      "QuickCountView should show 'Adjust by' segment")
    }

    /// Stepper − and + buttons must be present in QuickCountView.
    @MainActor
    func testQuickCountViewStepperButtons() throws {
        let app = try launchedApp()
        try openAuditTab(app)

        let card = firstAuditCard(app)
        guard card.exists else {
            throw XCTSkip("No audit items — seed required.")
        }
        card.tap()

        XCTAssertTrue(app.buttons["Decrease by 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Increase by 1"].exists)
    }

    /// Tapping + once in Set-to mode populates the New Quantity field.
    @MainActor
    func testStepperPlusIncrementsInSetToMode() throws {
        let app = try launchedApp()
        try openAuditTab(app)

        let card = firstAuditCard(app)
        guard card.exists else { throw XCTSkip("No audit items.") }
        card.tap()

        // Make sure Set-to mode is active (it's the default, but be explicit).
        let setToSegment = app.buttons["Set to"]
        if setToSegment.waitForExistence(timeout: 5) { setToSegment.tap() }

        let plusBtn = app.buttons["Increase by 1"]
        XCTAssertTrue(plusBtn.waitForExistence(timeout: 3))
        plusBtn.tap()

        let qtyField = app.textFields["New Quantity"]
        XCTAssertTrue(qtyField.waitForExistence(timeout: 3))

        let value = qtyField.value as? String ?? ""
        XCTAssertFalse(value.isEmpty,
                       "New Quantity field should be non-empty after tapping +")
    }

    /// Switching to Adjust-by mode shows the hint label.
    @MainActor
    func testAdjustByModeShowsHint() throws {
        let app = try launchedApp()
        try openAuditTab(app)

        let card = firstAuditCard(app)
        guard card.exists else { throw XCTSkip("No audit items.") }
        card.tap()

        let adjustBy = app.buttons["Adjust by"]
        XCTAssertTrue(adjustBy.waitForExistence(timeout: 5))
        adjustBy.tap()

        let hint = app.staticTexts["Negative values reduce stock"]
        XCTAssertTrue(hint.waitForExistence(timeout: 3),
                      "Adjust-by mode should display the 'Negative values reduce stock' hint")
    }

    /// In Adjust-by mode the field is labeled "Adjustment Amount".
    @MainActor
    func testAdjustByFieldHasCorrectAccessibilityLabel() throws {
        let app = try launchedApp()
        try openAuditTab(app)

        let card = firstAuditCard(app)
        guard card.exists else { throw XCTSkip("No audit items.") }
        card.tap()

        app.buttons["Adjust by"].tap()
        let field = app.textFields["Adjustment Amount"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - M3: Calculator
    // ──────────────────────────────────────────────────────────────────────

    /// Calculator button must be visible inside QuickCountView.
    @MainActor
    func testCalculatorButtonExists() throws {
        let app = try launchedApp()
        try openAuditTab(app)

        let card = firstAuditCard(app)
        guard card.exists else { throw XCTSkip("No audit items.") }
        card.tap()

        XCTAssertTrue(app.buttons["Calculator"].waitForExistence(timeout: 5))
    }

    /// Tapping Calculator opens the calculator sheet.
    @MainActor
    func testCalculatorOpens() throws {
        let app = try launchedApp()
        try openAuditTab(app)

        let card = firstAuditCard(app)
        guard card.exists else { throw XCTSkip("No audit items.") }
        card.tap()

        let calcBtn = app.buttons["Calculator"]
        XCTAssertTrue(calcBtn.waitForExistence(timeout: 5))
        calcBtn.tap()

        XCTAssertTrue(app.navigationBars["Calculator"].waitForExistence(timeout: 5),
                      "Calculator sheet should be visible")
    }

    /// 3 × 4 = 12; tapping "Use" returns the value to the New Quantity field.
    @MainActor
    func testCalculatorUseResult() throws {
        let app = try launchedApp()
        try openAuditTab(app)

        let card = firstAuditCard(app)
        guard card.exists else { throw XCTSkip("No audit items.") }
        card.tap()

        // Make sure we're in Set-to mode so calculator result lands in
        // `New Quantity` (Adjust-by would land in `Adjustment Amount`).
        if app.buttons["Set to"].waitForExistence(timeout: 5) {
            app.buttons["Set to"].tap()
        }

        // Open the calculator. (Opening it tends to dismiss the in-progress
        // decimalPad keyboard, which would otherwise cover the calc grid.)
        let calcBtn = app.buttons["Calculator"]
        XCTAssertTrue(calcBtn.waitForExistence(timeout: 5))
        calcBtn.tap()

        XCTAssertTrue(app.navigationBars["Calculator"].waitForExistence(timeout: 5))

        // Calculator labels: digits "0"–"9", "×", "÷", "+", "−" (U+2212), "=", "Use".
        // Use first matching to disambiguate from the system keyboard if it's still up.
        app.buttons["3"].firstMatch.tap()
        app.buttons["×"].firstMatch.tap()
        app.buttons["4"].firstMatch.tap()
        app.buttons["="].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["12"].waitForExistence(timeout: 3),
                      "Calculator display should show 12 after 3 × 4 =")

        app.buttons["Use"].firstMatch.tap()

        let qtyField = app.textFields["New Quantity"]
        XCTAssertTrue(qtyField.waitForExistence(timeout: 3))
        XCTAssertEqual(qtyField.value as? String, "12",
                       "Quantity field should reflect the calculator result")
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - M4: ItemDetailView
    // ──────────────────────────────────────────────────────────────────────

    /// Opening an item from the Items tab shows the redesigned detail view.
    @MainActor
    func testItemDetailViewLoads() throws {
        let app = try launchedApp()
        try openItemsTab(app)

        let row = firstItemRow(app)
        guard row.exists else {
            throw XCTSkip("No items in the Items tab — seed required.")
        }
        row.tap()

        // The "Count Item" CTA is rendered as a `.borderedProminent` button.
        XCTAssertTrue(app.buttons["Count Item"].waitForExistence(timeout: 5))
    }

    /// Item Detail shows "Item Info" section header (rendered uppercase).
    @MainActor
    func testItemDetailInfoSectionExists() throws {
        let app = try launchedApp()
        try openItemsTab(app)

        let row = firstItemRow(app)
        guard row.exists else { throw XCTSkip("No items.") }
        row.tap()

        // `.textCase(.uppercase)` renders the title fully uppercased.
        let info = app.staticTexts["ITEM INFO"]
        let infoFallback = app.staticTexts["Item Info"]
        XCTAssertTrue(info.waitForExistence(timeout: 5) || infoFallback.exists,
                      "Item Detail should show an 'Item Info' section header")
    }

    /// Item Detail shows "Storage & Limits" section header.
    @MainActor
    func testItemDetailStorageSectionExists() throws {
        let app = try launchedApp()
        try openItemsTab(app)

        let row = firstItemRow(app)
        guard row.exists else { throw XCTSkip("No items.") }
        row.tap()

        let upper = app.staticTexts["STORAGE & LIMITS"]
        let mixed = app.staticTexts["Storage & Limits"]
        XCTAssertTrue(upper.waitForExistence(timeout: 5) || mixed.exists,
                      "Item Detail should show a 'Storage & Limits' section header")
    }

    /// Edit (pencil) and Delete (trash) toolbar buttons must be present.
    @MainActor
    func testItemDetailToolbarButtons() throws {
        let app = try launchedApp()
        try openItemsTab(app)

        let row = firstItemRow(app)
        guard row.exists else { throw XCTSkip("No items.") }
        row.tap()

        // SwiftUI ToolbarItems with `Image(systemName: "pencil")` use the
        // SF Symbol name as the default accessibility label.
        let pencil = app.buttons["pencil"]
        let trash  = app.buttons["trash"]
        XCTAssertTrue(pencil.waitForExistence(timeout: 5),
                      "Edit (pencil) toolbar button should exist")
        XCTAssertTrue(trash.exists,
                      "Delete (trash) toolbar button should exist")
    }

    /// "Count Item" button in Item Detail opens QuickCountView.
    @MainActor
    func testItemDetailCountItemButton() throws {
        let app = try launchedApp()
        try openItemsTab(app)

        let row = firstItemRow(app)
        guard row.exists else { throw XCTSkip("No items.") }
        row.tap()

        let countItemBtn = app.buttons["Count Item"]
        XCTAssertTrue(countItemBtn.waitForExistence(timeout: 5))
        countItemBtn.tap()

        XCTAssertTrue(app.navigationBars["Quick Count"].waitForExistence(timeout: 5),
                      "Tapping Count Item should present the Quick Count sheet")
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - M5: Chart enhancements
    // ──────────────────────────────────────────────────────────────────────

    /// Item Detail should expose the "Quantity Trend" section header (text is
    /// rendered uppercase via `.textCase(.uppercase)`). The section is always
    /// emitted — it switches between the chart body and the empty state based
    /// on `dataPoints.count`, but the header is always visible.
    @MainActor
    func testTrendChartAppearsInItemDetail() throws {
        let app = try launchedApp()
        try openItemsTab(app)

        let row = firstItemRow(app)
        guard row.exists else {
            throw XCTSkip("Seed data required: at least one item in the Items tab.")
        }
        row.tap()

        let trendUpper = app.staticTexts["QUANTITY TREND"]
        let trendMixed = app.staticTexts["Quantity Trend"]

        // The detail view scrolls; nudge if the header isn't visible yet.
        if !trendUpper.waitForExistence(timeout: 3) && !trendMixed.exists {
            app.swipeUp()
        }
        XCTAssertTrue(trendUpper.waitForExistence(timeout: 3) || trendMixed.exists,
                      "Item Detail should display a 'Quantity Trend' section")
    }

    /// Tapping the "Expiring Soon" Dashboard card opens ExpiryTimelineView.
    @MainActor
    func testExpiryTimelineOpensFromDashboard() throws {
        let app = try launchedApp()
        try openDashboardTab(app)

        // DashboardCard is rendered as a `Button` whose accessibility label
        // includes the title "Expiring Soon" and the count value.
        let card = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Expiring'")
        ).firstMatch

        guard card.waitForExistence(timeout: 5) else {
            throw XCTSkip("Seed data required: 'Expiring Soon' card not present on Dashboard.")
        }
        card.tap()

        XCTAssertTrue(app.navigationBars["Expiry Timeline"].waitForExistence(timeout: 5),
                      "Tapping the Expiring Soon card should present ExpiryTimelineView")
    }

    /// "Done" in ExpiryTimelineView's nav bar dismisses the sheet.
    @MainActor
    func testExpiryTimelineDoneButtonDismisses() throws {
        let app = try launchedApp()
        try openDashboardTab(app)

        let card = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Expiring'")
        ).firstMatch

        guard card.waitForExistence(timeout: 5) else {
            throw XCTSkip("Seed data required: 'Expiring Soon' card not present on Dashboard.")
        }
        card.tap()

        let nav = app.navigationBars["Expiry Timeline"]
        guard nav.waitForExistence(timeout: 5) else {
            throw XCTSkip("ExpiryTimelineView did not appear — cannot test Done button.")
        }

        // Scope to the nav bar to avoid matching any stray "Done" buttons
        // (e.g. on a keyboard accessory toolbar somewhere on screen).
        nav.buttons["Done"].tap()

        // After dismissal, allow the sheet animation to finish, then verify
        // the nav bar is no longer in the hierarchy.
        let predicate = NSPredicate(format: "exists == false")
        expectation(for: predicate, evaluatedWith: nav, handler: nil)
        waitForExpectations(timeout: 3)
    }

    /// Dashboard should display the "Value by Category" chart (M5c).
    @MainActor
    func testCategoryValueChartAppearsOnDashboard() throws {
        let app = try launchedApp()
        try openDashboardTab(app)

        let valueHeader = app.staticTexts["Value by Category"]

        // Dashboard scrolls — the chart sits below the stat cards and the
        // stock CategoryBarChart, so we may need to scroll to reveal it.
        if !valueHeader.waitForExistence(timeout: 3) {
            app.swipeUp()
            if !valueHeader.waitForExistence(timeout: 2) { app.swipeUp() }
        }

        XCTAssertTrue(valueHeader.waitForExistence(timeout: 3),
                      "Dashboard should display the 'Value by Category' chart")
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - Launch performance (existing)
    // ──────────────────────────────────────────────────────────────────────

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
