# Phase 7A QA Test Plan — Sales, Profitability & Reports
**Role:** QA Engineer  
**Date:** 2026-06-27  
**Based on:** `phase7-prd.md` + `phase7-ux-spec.md`  
**App:** Stoqly · Bundle ID: `com.vishuddhi.stoqly`  
**Test account:** `test@smartinventory.dev` / `Test@1234`  
**Status:** READY FOR EXECUTION

---

## Coverage Summary

| Area | Test Cases | Maestro Flows |
|------|-----------|---------------|
| Selling Price | 12 | 88 (YAML below) |
| Quick Sale | 14 | 88 (YAML below) |
| Inventory Movements | 12 | 89 (YAML below) |
| Profitability Section | 10 | 88 (YAML below) |
| Reports Screen | 16 | 90 (YAML below) |
| Dashboard Sales Performance | 8 | — |
| Currency Auto-Detect | 10 | 92 (YAML below) |
| Bug Fix — Value by Category | 6 | — |
| Bug Fix — Dead Stock Grace Period | 6 | — |
| Bug Fix — Settings Cleanup | 6 | — |
| Bug Fix — Currency Consistency | 6 | 92 (YAML below) |
| Bug Fix — Dark Mode Cards | 6 | — |
| **Total** | **112** | **5 new flows** |

---

---

# SECTION 1: Manual Test Checklist

All tests run on a physical iPhone (iOS 17+). Dark mode tests require toggling in Control Center or Settings. Accessibility tests require VoiceOver enabled.

---

## 1.1 Selling Price on Items

### Pre-condition
Signed in as test user. "Test Product Maestro" exists in Test Warehouse with unit cost = 10.00 and sellingPrice = 0.

### Happy Paths

- [ ] **SP-H1** Open Edit Item for "Test Product Maestro". Confirm a "Selling Price" field appears **below** the "Unit Cost" field. Field has a currency symbol prefix matching the currently selected currency.
- [ ] **SP-H2** Enter unit cost = 100, selling price = 150. Confirm live margin caption below the selling price field reads "Margin: 33%" in **green** (margin > 30%). Tap Save. Navigate to ItemDetailView. Confirm Profitability section shows Cost = 100, Selling Price = 150, Profit/unit = 50, Gross Margin = 33% in green.
- [ ] **SP-H3** Enter unit cost = 80, selling price = 100. Confirm live margin = "Margin: 20%" in **orange** (10–30% range).
- [ ] **SP-H4** Enter unit cost = 95, selling price = 100. Confirm live margin = "Margin: 5%" in **red** (< 10% range).
- [ ] **SP-H5** Set selling price > 0, save item. Selling price persists when reopening Edit Item.
- [ ] **SP-H6** Add a **new** item with unit cost = 50 and selling price = 75. Save. Confirm the new item's detail shows "Margin: 33%" in green immediately (no re-launch required).

### Edge Cases

- [ ] **SP-E1** Leave selling price field blank (0). Confirm the margin caption is **hidden** entirely (no "0%" or "Margin: —" displayed). Confirm item saves successfully.
- [ ] **SP-E2** Set selling price = 0 explicitly. Confirm same as SP-E1 (margin hidden, no warning about loss).
- [ ] **SP-E3** Set selling price = 5, unit cost = 10 (selling below cost). Confirm margin caption reads in **red** with supplementary warning: "Selling below cost" (or equivalent loss warning copy). Confirm Save is still **enabled** (user can save a loss item).
- [ ] **SP-E4** Set unit cost = 0, selling price = 50. Confirm margin displays "100%" (or equivalent — cost not contributing). Confirm no division-by-zero crash.
- [ ] **SP-E5** Edit item to set selling price = 150 after historical SaleEvents already exist. Confirm old SaleEvents in Reports still show the **historical** price that was recorded at sale time — not the new selling price.

### CSV/Excel Bulk Import

- [ ] **SP-I1** Prepare a CSV with column header exactly "Selling Price". Import it. Confirm the sellingPrice field maps correctly (value appears in Edit Item after import).
- [ ] **SP-I2** Prepare a CSV with column header "MRP". Import it. Confirm it also maps to sellingPrice.
- [ ] **SP-I3** Prepare a CSV with column header "sale price" (lowercase). Confirm it also maps to sellingPrice (case-insensitive match per UX spec: ["selling price", "sale price", "mrp", "retail price", "price"]).

### Accessibility

- [ ] **SP-A1** With VoiceOver enabled, navigate to the Selling Price field in Edit Item. Confirm VoiceOver announces: "Selling price per unit, text field".
- [ ] **SP-A2** With VoiceOver, navigate to the live margin caption. Confirm it reads the margin value and color context aloud (e.g., "Margin 33 percent, good margin").

### Dark Mode

- [ ] **SP-DM1** Toggle to dark mode. Open Edit Item with selling price set. Confirm the margin caption is readable against the dark background (not washed out green-on-black).

---

## 1.2 Quick Sale Recording

### Pre-condition
"Test Product Maestro" exists with currentQuantity = 50, sellingPrice = 150, unitCost = 100. User is signed in.

### Happy Paths

- [ ] **QS-H1** From ItemDetailView for "Test Product Maestro", tap "Record Sale" button. Confirm QuickSaleSheet opens. Confirm it shows: item name "Test Product Maestro", current stock "50", default selling price pre-filled = 150, and an empty quantity field.
- [ ] **QS-H2** In QuickSaleSheet, enter quantity = 5. Confirm the live Revenue/Profit/Margin preview row updates: Revenue = 750, Profit = 250, Margin = 33%.
- [ ] **QS-H3** Tap Save. Confirm: (a) QuickSaleSheet dismisses, (b) a toast/banner "Sale recorded" appears briefly on the parent screen, (c) item's `currentQuantity` has decreased to 45, (d) a SaleEvent was created (verify via ActivityFeed showing "SaleMade" event), (e) the ActivityFeed shows the item name and quantity sold.
- [ ] **QS-H4** From StorageDetailView, swipe **right** on any item row. Confirm TWO leading swipe actions appear: "Count" (green, outermost) and "Sale" (teal, second). Tap "Sale". Confirm QuickSaleSheet opens for that item.
- [ ] **QS-H5** In QuickSaleSheet, change the selling price from the pre-filled default to a different value (e.g., 180). Tap Save. Verify in the SaleEvent (via ActivityFeed detail or Reports) that the recorded price = 180, not 150.
- [ ] **QS-H6** Set a date in QuickSaleSheet (tap the date field, pick yesterday). Confirm the SaleEvent is recorded with yesterday's date (visible in Activity Feed with correct timestamp).

### Edge Cases

- [ ] **QS-E1** Enter quantity = 0 in QuickSaleSheet. Confirm the "Save" button is **disabled**. No tap-through.
- [ ] **QS-E2** Enter quantity = 60 (exceeds current stock of 50). Confirm an orange warning banner appears: "Selling more than in stock (have: 50). Sale will record a negative stock." Confirm Save is **still enabled** (override allowed). Tap Save. Confirm stock goes to -10 (negative stock is permitted per PRD).
- [ ] **QS-E3** Item has sellingPrice = 0 AND selling price field in QuickSaleSheet is also 0. Confirm the Revenue/Profit/Margin preview row is **hidden**. Confirm a caption reads: "No selling price — profit won't be tracked". Confirm Save still works (revenue not tracked).
- [ ] **QS-E4** Item has sellingPrice > 0 but user clears the price field in QuickSaleSheet to 0. Confirm a "Use default price" link appears. Tapping it restores the item's sellingPrice.
- [ ] **QS-E5** Record sale when item.currentQuantity = 0. Confirm "Record Sale" button is visible but slightly dimmed, and a caption reads "Out of stock — sale will create negative stock". Confirm tapping still opens QuickSaleSheet (backorders allowed).

### Error States

- [ ] **QS-Err1** Simulate offline (Airplane mode). Attempt to record a sale. Confirm the app shows an alert: "Failed to record sale. Check your connection." (or equivalent). Confirm no stock deduction occurred. Confirm no partial SaleEvent was created.

### Haptics & Feedback

- [ ] **QS-UX1** After a successful sale, confirm a haptic success feedback fires (device vibrates once with a "success" pattern — `.notificationOccurred(.success)`).
- [ ] **QS-UX2** Confirm tapping Cancel in QuickSaleSheet dismisses the sheet with no stock change.

### Accessibility

- [ ] **QS-A1** With VoiceOver, confirm quantity stepper buttons announce: "Decrease quantity, button" and "Increase quantity, button".
- [ ] **QS-A2** With VoiceOver, confirm the live calculation row (Revenue/Profit/Margin) is announced as a single combined element: "Revenue [amount], Profit [amount], Margin [pct] percent".

### Dark Mode

- [ ] **QS-DM1** Open QuickSaleSheet in dark mode. Confirm the live Revenue/Profit/Margin preview card uses an appropriate teal/elevated background — not pure black matching the sheet background.

---

## 1.3 Inventory Movement Logging

### Pre-condition
"Test Product Maestro" with currentQuantity = 50 exists. User is on ItemDetailView.

### Happy Paths — IN Types

- [ ] **IM-H1** Tap "Add Movement" (secondary action on ItemDetailView). Confirm MovementSheet opens with "Add Movement" title, IN/OUT direction segment defaulting to IN, and type picker defaulting to "Purchase".
- [ ] **IM-H2** Select direction = IN, type = "Purchase", qty = 10, purchase price = 12.00. Tap Add. Confirm: (a) stock increases from 50 to 60, (b) InventoryMovement record created, (c) ActivityFeed shows "MovementLogged" event, (d) price label in the sheet was "Purchase Price per Unit".
- [ ] **IM-H3** Select IN → "Transfer In", qty = 5. Tap Add. Confirm stock goes to 65.
- [ ] **IM-H4** Select IN → "Return from Customer", qty = 2. Tap Add. Confirm stock goes to 67.
- [ ] **IM-H5** Select IN → "Adjustment (Up)", qty = 3. Confirm stock goes to 70.
- [ ] **IM-H6** Select IN → "Opening Stock", qty = 100. Confirm stock increases by 100.

### Happy Paths — OUT Types

- [ ] **IM-H7** Select direction = OUT, type = "Waste / Spoilage" (default for OUT), qty = 4. Price label must read "Wasted Value per Unit". Tap Add. Confirm stock decreases by 4. Confirm ActivityFeed shows "MovementLogged" event.
- [ ] **IM-H8** Select OUT → "Transfer Out", qty = 6. Confirm stock decreases by 6.
- [ ] **IM-H9** Select OUT → "Return to Supplier", qty = 2. Confirm stock decreases by 2.
- [ ] **IM-H10** Select OUT → "Adjustment (Down)", qty = 5. Confirm stock decreases by 5.

### Special Case — Sale Type in OUT

- [ ] **IM-H11** Select direction = OUT, type = "Sale". Confirm MovementSheet **dismisses** and QuickSaleSheet opens instead (Sale is a passthrough to Flow 2, not a direct movement entry).

### Edge Cases

- [ ] **IM-E1** Enter quantity = 0 in MovementSheet. Confirm the "Add" button is **disabled**.
- [ ] **IM-E2** Select Purchase (IN). Confirm price field is pre-filled with item's unitCost (e.g., 100). Edit it to a different value and confirm the save succeeds with the new price.
- [ ] **IM-E3** Select Waste (OUT). Confirm price field is pre-filled with item's unitCost. Clear the price field entirely — confirm Add remains enabled (price is optional).
- [ ] **IM-E4** Leave the notes field empty. Confirm the movement saves without error (notes are optional).
- [ ] **IM-E5** Change the date to 3 days ago. Confirm the saved InventoryMovement record reflects that backdated date (visible in MovementsListView with the correct date section header).

### Accessibility

- [ ] **IM-A1** With VoiceOver, confirm direction segment announces "Movement direction, segmented control, IN selected" (or equivalent).
- [ ] **IM-A2** With VoiceOver, confirm type picker announces "Movement type" as its label.

### Dark Mode

- [ ] **IM-DM1** Open MovementSheet in dark mode. Confirm all sections (direction picker, type picker, quantity field, price field) have readable contrast.

---

## 1.4 Profitability Section in ItemDetailView

### Pre-condition
Two test items: "Item With Margin" (unitCost = 100, sellingPrice = 150) and "Item No Price" (unitCost = 50, sellingPrice = 0).

### State A — Selling Price Set

- [ ] **PF-H1** Open ItemDetailView for "Item With Margin". Scroll to find the "Profitability" section (appears between stock stats and count history). Confirm it shows:
  - "Cost" row = 100.00 (in current currency)
  - "Selling Price" row = 150.00
  - "Profit/unit" row = 50.00 in **green** text
  - "Gross Margin" row = "33%" in **green** text
- [ ] **PF-H2** For an item with 10–30% margin (e.g., cost = 80, price = 100): confirm Profit/unit and Gross Margin rows appear in **orange**.
- [ ] **PF-H3** For an item with < 10% margin (e.g., cost = 95, price = 100): confirm Profit/unit and Gross Margin rows appear in **red**.
- [ ] **PF-H4** For an item with selling price < unit cost (e.g., cost = 120, price = 100): confirm Gross Margin is **negative**, shown in red. Confirm no crash from negative margin value.

### State B — No Selling Price Set

- [ ] **PF-H5** Open ItemDetailView for "Item No Price". Confirm the Profitability section shows: "Set a selling price to track your profit margin for this item." and a blue tappable link "Set Selling Price →".
- [ ] **PF-H6** Tap "Set Selling Price →" in the Profitability section. Confirm EditItemView opens, pre-scrolled or focused at the Selling Price field.
- [ ] **PF-H7** The Profitability section must **not** show "0%" margin or any monetary calculation when sellingPrice = 0.

### Reports — Top Performers (sub-view)

- [ ] **PF-R1** Open ReportsView. Confirm "Top Items by Revenue" section lists items with selling prices ranked by revenue (highest first).
- [ ] **PF-R2** Each row in the Top Items list shows: item name, quantity sold, and revenue amount in the current currency symbol.

### Reports — Margin Alerts (sub-view)

- [ ] **PF-R3** In ReportsView "Margin Alerts" section: items with margin < 10% appear labeled "Low margin" in **orange**.
- [ ] **PF-R4** Items where sellingPrice ≤ unitCost appear labeled "Selling at a loss" in **red**.
- [ ] **PF-R5** Items with margin ≥ 10% do NOT appear in the Margin Alerts section.

### Accessibility

- [ ] **PF-A1** With VoiceOver, confirm the Profitability card is announced with all four values combined: "Profitability. Cost [amount]. Selling Price [amount]. Profit per unit [amount]. Gross Margin [pct] percent."

---

## 1.5 Reports Screen

### Pre-condition
At least 3 SaleEvents exist across different days: 2 from "today", 1 from 3 days ago. Items have sellingPrice and unitCost set.

### Period Picker

- [ ] **REP-H1** Open ReportsView (Dashboard → Sales Performance → "View Full Report →"). Confirm period picker shows: "Today" | "This Week" | "This Month" | "Custom". "Today" is selected by default.
- [ ] **REP-H2** Tap "This Week". Confirm the Summary Card updates to show revenue/COGS/profit/margin for the current week. Confirm the revenue trend chart shows daily bars for the current week.
- [ ] **REP-H3** Tap "This Month". Confirm chart shows weekly bars (not daily). Confirm metrics update.

### Summary Card

- [ ] **REP-H4** With "Today" selected and 2 sales recorded today (e.g., 2 × 5 kg of "Test Product" at ₹150/unit, cost ₹100/unit): confirm Summary Card shows:
  - Revenue = ₹1,500 (2 × 5 × 150)
  - COGS = ₹1,000 (2 × 5 × 100)
  - Gross Profit = ₹500
  - Gross Margin = 33%
- [ ] **REP-H5** The Summary Card shows 3 horizontal bars: revenue (full width), COGS (proportional), profit (proportional). Bars use correct colors: blue for revenue, orange for COGS, green for profit.

### Revenue Trend Chart

- [ ] **REP-H6** The Revenue Trend bar chart renders without crash. Bars correspond to the selected period (daily for Today/Week, weekly for Month). Tap a bar — confirm a callout shows date + revenue value.

### Top Items List

- [ ] **REP-H7** "Top Items by Revenue" section appears and is non-empty. Items are ranked by revenue descending. Each row shows: rank, item name, quantity sold (with UOM abbreviation), and revenue in correct currency.

### Margin Alerts

- [ ] **REP-H8** If any sold item has margin < 10%, a "Margin Alerts" section appears with the item name, margin %, and "Low margin" or "Selling at a loss" label. Tapping the item navigates to ItemDetailView.
- [ ] **REP-H9** If no items have low margin, the "Margin Alerts" section is hidden entirely (no empty "Margin Alerts" card).

### Inventory Movements Summary

- [ ] **REP-H10** "Inventory Movements" (collapsible section) shows total IN units/value and total OUT units for the period. Breakdown shows: Sales OUT and Waste OUT as separate sub-rows.
- [ ] **REP-H11** Tap "View All Movements →". Confirm MovementsListView opens inside the same sheet stack with the same period inherited. Confirm movements are grouped by date section.

### Empty State

- [ ] **REP-E1** Switch to a period with **no** sales (e.g., "Today" when no sales recorded today). Confirm `ContentUnavailableView` appears with: title "No Sales This Period", system image "cart.badge.minus", description "Record sales from any item to see revenue and profit here.", and a "How to Record a Sale" CTA button.
- [ ] **REP-E2** The empty state does NOT show a blank screen, a 0-revenue summary card, or a crash.

### Pro Gating

- [ ] **REP-P1** As a **Free** user, tap "Custom" in the period picker. Confirm a paywall sheet appears. Confirm "Today", "This Week", "This Month" still work without paywall.
- [ ] **REP-P2** As a **Pro** user, tap "Custom". Confirm a date range picker appears. Select a custom range. Confirm the report loads for that range.
- [ ] **REP-P3** Free user with data older than 30 days: confirm older data is either blurred or a Pro upgrade prompt appears for historical access.

### Dark Mode

- [ ] **REP-DM1** Open ReportsView in dark mode. Confirm Summary Card uses `Color(.secondarySystemGroupedBackground)` — visually distinct from the sheet background (not merged/invisible).
- [ ] **REP-DM2** In dark mode, Margin Alert card (orange-tinted) remains readable — not too dark/invisible.
- [ ] **REP-DM3** Revenue Trend chart renders correctly in dark mode (axis labels readable, bars visible).

### Accessibility

- [ ] **REP-A1** With VoiceOver, period picker announces: "Report period selector".
- [ ] **REP-A2** With VoiceOver, Summary Card reads all four metrics as a combined element: "Summary. Revenue [amount]. COGS [amount]. Gross Profit [amount]. Gross Margin [pct] percent."
- [ ] **REP-A3** With VoiceOver, Revenue Trend chart announces: "Revenue chart for [period]. Highest day [date] at [amount]."
- [ ] **REP-A4** Each row in Top Items announces: "[Item name]. [qty] sold. Revenue [amount]."
- [ ] **REP-A5** "Custom" pill with Pro lock announces: "Custom period. Pro feature."

---

## 1.6 Dashboard — Sales Performance Section

### Pre-condition
Test account has at least 1 item with sellingPrice > 0 OR at least 1 SaleEvent.

### Visibility Logic

- [ ] **DASH-H1** Dashboard with qualifying data: scroll past Smart Insights section. Confirm a "Sales Performance" section exists with a period picker and a mini bar chart.
- [ ] **DASH-H2** Sales Performance section shows inline stats: Revenue, Profit, Margin % for the selected period.
- [ ] **DASH-H3** "View Full Report →" row appears at the bottom of the Sales Performance section. Tapping it opens ReportsView as a `.sheet`.
- [ ] **DASH-H4** Period picker in Sales Performance section functions: Today / This Week / This Month. Switching period updates the inline stats and mini chart.
- [ ] **DASH-H5** When user picks "This Week" in the Sales Performance section, ReportsView opens defaulting to "This Week" (period selection is passed through, not reset to "Today").

### Empty State (New User)

- [ ] **DASH-E1** Brand new account with 0 items and 0 sales: confirm the "Sales Performance" section is **hidden entirely**. The dashboard should not show the section header or an empty state card for sales.
- [ ] **DASH-E2** Account with ≥ 1 item with sellingPrice > 0 but 0 sales: confirm Sales Performance section appears with an empty state: "No sales recorded yet. Start recording sales to see your profit insights here." and a "Record Your First Sale →" CTA.

### Dark Mode

- [ ] **DASH-DM1** Sales Performance section in dark mode: the card background is elevated (not merged with the Dashboard page background).

---

## 1.7 Currency Auto-Detection

### Pre-condition
Fresh app install (clearState). Device locale.

### First Install

- [ ] **CUR-H1** Install on a device with region = India (en_IN). Launch for the first time. Confirm the currency in Settings → Currency picker shows "Indian Rupee (₹)" selected automatically. Confirm **no** prompt or alert was shown — it's silent.
- [ ] **CUR-H2** Install on a device with region = United States (en_US). Launch. Confirm currency = USD ($) set automatically. Silent.
- [ ] **CUR-H3** Install on a device with an unsupported locale (e.g., en_AQ — Antarctic). Launch. Confirm currency falls back to USD. No crash.
- [ ] **CUR-H4** Install with en_IN, then manually change currency to USD in Settings. Kill and relaunch the app. Confirm currency remains USD (manual override persists, no silent revert to INR).

### Locale Change Detection

- [ ] **CUR-H5** On a device previously set to en_US (USD saved), change device region to India (en_IN) in iOS Settings. Return to Stoqly (foreground). Confirm a banner appears at the top of Dashboard: "Your region changed to India. Switch to Indian Rupee (₹)?" with two buttons: "Switch to ₹" and "Keep USD".
- [ ] **CUR-H6** Tap "Switch to ₹". Confirm the banner dismisses. Confirm all monetary values on Dashboard now show ₹.
- [ ] **CUR-H7** Repeat CUR-H5 for a different test session. This time tap "Keep USD". Confirm banner dismisses. Confirm currency stays USD. Confirm the banner does **not** appear again on subsequent app launches for the same locale change (dismissed flag saved).
- [ ] **CUR-H8** The locale-change banner auto-dismisses after 8 seconds if not tapped (defaults to "keep current" behavior). Confirm currency did not change.
- [ ] **CUR-H9** The locale-change prompt fires **only once** per unique locale change. If user already dismissed the INR prompt, changing back to en_US and then back to en_IN again does NOT show the INR banner again.
- [ ] **CUR-H10** Locale detection works **offline** (no internet connection). First install with en_IN locale and Airplane mode on: currency still defaults to ₹ (Locale.current is device-local, no network call).

---

---

# SECTION 2: Maestro Flow Specs (Flows 88–92)

**Note:** Existing flows 81–87 cover Smart Count. Phase 7A flows begin at 88.

---

## Flow 88 — `88_selling_price_and_margin.yaml`

Tests setting a selling price on an existing item and verifying the margin calculation displays correctly in both EditItemView (live) and ItemDetailView (saved state).

```yaml
# Flow 88 — Selling Price Field and Margin Display
# Tests: Enter selling price → live margin in edit form → saved margin in ItemDetailView
# Pre-condition: Test Product Maestro exists with unitCost set and sellingPrice = 0
appId: com.vishuddhi.stoqly
---
- runFlow: 00_signin_helper.yaml

# Navigate to Test Product Maestro
- runFlow: open_test_product_detail.yaml

# Open edit from ItemDetailView
- tapOn: "Edit"
- assertVisible: "Edit Item"

# Scroll to Selling Price field (below Unit Cost)
- scrollUntilVisible:
    element:
      id: "sellingPriceField"
    direction: DOWN
    timeout: 15000
    visibilityPercentage: 50
- tapOn:
    id: "sellingPriceField"
- eraseText: 10
- inputText: "150"
- tapOn:
    text: "Done"
    optional: true

# Verify live margin caption appears (unit cost = 100, selling price = 150 → 33%)
- assertVisible:
    id: "marginCaption"
- assertVisible: "33%"

# Save the item
- tapOn: "Save"
- waitForAnimationToEnd

# Confirm we're back on ItemDetailView for Test Product Maestro
- assertVisible: "Test Product Maestro"

# Scroll to Profitability section
- scrollUntilVisible:
    element: "PROFITABILITY"
    direction: DOWN
    timeout: 15000
    optional: true
- scrollUntilVisible:
    element:
      id: "profitabilitySection"
    direction: DOWN
    timeout: 15000
    optional: true

# Verify profitability values
- assertVisible: "150"
- assertVisible: "33%"

# Now test the "below cost" warning: edit item to set selling price < unit cost
- tapOn: "Edit"
- scrollUntilVisible:
    element:
      id: "sellingPriceField"
    direction: DOWN
    timeout: 15000
- tapOn:
    id: "sellingPriceField"
- eraseText: 10
- inputText: "80"
- tapOn:
    text: "Done"
    optional: true

# Verify loss warning appears
- assertVisible:
    id: "sellingBelowCostWarning"
    optional: true
- assertVisible: "Selling below cost"
    optional: true

# Reset selling price to a valid value and save
- tapOn:
    id: "sellingPriceField"
- eraseText: 10
- inputText: "150"
- tapOn: "Save"
- assertVisible: "Test Product Maestro"
```

---

## Flow 89 — `89_record_quick_sale.yaml`

Tests recording a Quick Sale from ItemDetailView: opens QuickSaleSheet, enters a quantity, confirms the live profit preview, saves, and verifies stock has decreased.

```yaml
# Flow 89 — Record Quick Sale from ItemDetailView
# Tests: Open QuickSaleSheet → set qty → verify profit preview → save → verify stock decreases
# Pre-condition: Test Product Maestro exists with currentQuantity = 50, sellingPrice = 150, unitCost = 100
appId: com.vishuddhi.stoqly
---
- runFlow: 00_signin_helper.yaml
- runFlow: open_test_product_detail.yaml

# Capture a visual baseline of stock (optional — for human review)
- assertVisible: "Count Item"

# Tap Record Sale button
- tapOn:
    id: "recordSaleButton"
- waitForAnimationToEnd

# QuickSaleSheet should be open
- assertVisible: "Record Sale"
- assertVisible: "Test Product Maestro"

# Verify selling price pre-filled
- assertVisible: "150"

# Enter quantity
- tapOn:
    id: "quickSaleQtyField"
- eraseText: 10
- inputText: "5"
- tapOn:
    text: "Done"
    optional: true
- waitForAnimationToEnd

# Verify live profit preview is visible (5 × 150 = 750 revenue, 5 × 50 = 250 profit)
- assertVisible:
    id: "saleProfitPreview"
- assertVisible: "750"
- assertVisible: "250"

# Save the sale
- tapOn: "Save"
- waitForAnimationToEnd

# Confirm dismissal and toast
- assertVisible: "Test Product Maestro"
- assertVisible:
    text: "Sale recorded"
    optional: true

# Verify stock decreased (50 - 5 = 45)
- scrollUntilVisible:
    element: "45"
    direction: DOWN
    timeout: 10000
    optional: true
- assertVisible:
    text: "45"
    optional: true

# Verify in Activity Feed
- tapOn: "Dashboard"
- scrollUntilVisible:
    element: "Recent Activity"
    direction: DOWN
    timeout: 10000
- assertVisible: "Test Product Maestro"
```

---

## Flow 90 — `90_add_inventory_movement_purchase.yaml`

Tests adding a Purchase (IN) movement from ItemDetailView and verifying the stock increases.

```yaml
# Flow 90 — Add Inventory Movement (Purchase IN)
# Tests: Open MovementSheet → select IN/Purchase → enter qty → save → verify stock increases
# Pre-condition: Test Product Maestro exists in Test Warehouse, currentQuantity = 50
appId: com.vishuddhi.stoqly
---
- runFlow: 00_signin_helper.yaml
- runFlow: open_test_product_detail.yaml

# Open Add Movement
- scrollUntilVisible:
    element:
      id: "addMovementButton"
    direction: DOWN
    timeout: 15000
- tapOn:
    id: "addMovementButton"
- waitForAnimationToEnd

# MovementSheet open
- assertVisible: "Add Movement"

# Direction: IN should be default
- assertVisible: "IN"

# Type: Purchase should be default for IN
- assertVisible: "Purchase"
    optional: true

# Enter quantity = 20
- tapOn:
    id: "movementQtyField"
- eraseText: 10
- inputText: "20"
- tapOn:
    text: "Done"
    optional: true

# Verify price label reads "Purchase Price per Unit"
- assertVisible: "Purchase Price"
    optional: true

# Enter purchase price
- tapOn:
    id: "movementPriceField"
    optional: true
- eraseText: 10
    optional: true
- inputText: "100"
    optional: true
- tapOn:
    text: "Done"
    optional: true

# Tap Add
- tapOn: "Add"
- waitForAnimationToEnd

# Confirm dismissal and success toast
- assertVisible: "Test Product Maestro"
- assertVisible:
    text: "Movement recorded"
    optional: true

# Verify stock increased (50 + 20 = 70)
- scrollUntilVisible:
    element: "70"
    direction: DOWN
    timeout: 10000
    optional: true
- assertVisible:
    text: "70"
    optional: true
```

---

## Flow 91 — `91_reports_view_period_switch.yaml`

Tests navigating to ReportsView from the Dashboard, switching between period options, and verifying the screen renders correctly for each period.

```yaml
# Flow 91 — Reports View — Period Switching
# Tests: Open ReportsView from Dashboard → switch period picker → verify screen updates
# Pre-condition: At least 1 SaleEvent exists so the report is not in empty state
appId: com.vishuddhi.stoqly
---
- runFlow: 00_signin_helper.yaml

# Navigate to Dashboard
- tapOn: "Dashboard"
- waitForAnimationToEnd

# Scroll to Sales Performance section
- scrollUntilVisible:
    element: "Sales Performance"
    direction: DOWN
    timeout: 15000
- assertVisible: "Sales Performance"

# Tap View Full Report
- tapOn: "View Full Report"
- waitForAnimationToEnd

# ReportsView should be open
- assertVisible: "Reports"

# Verify period picker is visible
- assertVisible: "Today"
- assertVisible: "This Week"
- assertVisible: "This Month"

# Switch to This Week
- tapOn: "This Week"
- waitForAnimationToEnd

# Verify summary card is visible (or empty state if no data this week)
- assertVisible:
    id: "reportsSummaryCard"
    optional: true
- assertVisible:
    text: "No Sales This Period"
    optional: true

# Switch to This Month
- tapOn: "This Month"
- waitForAnimationToEnd

# Verify screen still renders (no crash on period switch)
- assertVisible: "Reports"

# Verify movements section is accessible
- scrollUntilVisible:
    element: "Inventory Movements"
    direction: DOWN
    timeout: 15000
    optional: true

# Verify View All Movements link exists
- assertVisible:
    text: "View All Movements"
    optional: true

# Dismiss
- tapOn: "Done"
- waitForAnimationToEnd

# Should be back on Dashboard
- assertVisible: "Total Storages"
```

---

## Flow 92 — `92_currency_consistency_check.yaml`

Tests that changing the currency in Settings propagates correctly to StorageDetailView, ItemDetailView, and ValueByCategoryView — and that no view shows a stale "$" when currency is set to EUR.

```yaml
# Flow 92 — Currency Consistency Across Views
# Tests: Set currency to EUR → verify StorageDetailView, ItemDetailView show €, not $
# Tests: Set currency back to USD at end to clean up
appId: com.vishuddhi.stoqly
---
- runFlow: 00_signin_helper.yaml

# Change currency to EUR via Settings
- tapOn: "Dashboard"
- tapOn:
    id: "gear"
- assertVisible: "Settings"
- scrollUntilVisible:
    element:
      id: "settingsCurrencyPicker"
    direction: DOWN
    timeout: 10000
- tapOn:
    id: "settingsCurrencyPicker"
- tapOn:
    id: "currency_EUR"
- tapOn:
    text: "Settings"
    index: 0
- tapOn: "Done"

# Verify Dashboard Total Value shows € (not $)
- tapOn: "Dashboard"
- assertVisible: "€"
- assertNotVisible: "$"

# Verify StorageDetailView shows €
- tapOn: "Storages"
- tapOn: "Test Warehouse"
- assertVisible: "€"

# Scroll to item rows to confirm item prices also show €
- scrollUntilVisible:
    element: "Test Product Maestro"
    direction: DOWN
    timeout: 15000
- assertVisible: "Test Product Maestro"
- assertVisible: "€"

# Verify ItemDetailView shows €
- tapOn: "Test Product Maestro"
- waitForAnimationToEnd
- assertVisible: "€"
- assertNotVisible: "$"

# Dismiss ItemDetailView
- tapOn: "Back"
    optional: true
- tapOn: "Test Warehouse"
    optional: true

# Navigate to Dashboard and open Value by Category
- tapOn: "Dashboard"
- tapOn:
    id: "valueByCategoryLink"
    optional: true
- scrollUntilVisible:
    element: "Value by Category"
    direction: DOWN
    timeout: 15000
    optional: true
- tapOn: "Value by Category"
    optional: true
- assertVisible: "€"
    optional: true
- tapOn: "Back"
    optional: true
- tapOn: "Done"
    optional: true

# Reset currency back to USD for subsequent flows
- tapOn: "Dashboard"
- tapOn:
    id: "gear"
- scrollUntilVisible:
    element:
      id: "settingsCurrencyPicker"
    direction: DOWN
    timeout: 10000
- tapOn:
    id: "settingsCurrencyPicker"
- tapOn:
    id: "currency_USD"
- tapOn:
    text: "Settings"
    index: 0
- tapOn: "Done"
- assertVisible: "Dashboard"
```

---

---

# SECTION 3: Bug Regression Checklist

Each checklist item is written as explicit reproduction steps followed by the expected pass result. Run against a build where all 5 bug fixes are applied.

---

## Bug 1 — Value by Category: Empty State (Light + Dark Mode)

**Root cause:** Blank gray sheet instead of `ContentUnavailableView` when no items have unit costs.

### Steps

- [ ] **BUG1-1** Sign in to a test account with all items having unitCost = 0 (or no items). Navigate to Value by Category (Dashboard → Health Card → "Value by Category" or equivalent entry point).
  - **Pass:** `ContentUnavailableView` with title "No Category Values", system image "chart.pie", and description "Add items with a unit cost to see your inventory value by category." is displayed.
  - **Fail:** Blank area, floating "Total ₹0.00" text only, or gray void.

- [ ] **BUG1-2** Toggle dark mode (Control Center). Remain on the Value by Category view.
  - **Pass:** The sheet background uses `Color(.systemGroupedBackground)` — visually a dark elevated gray, NOT pure black. The `ContentUnavailableView` text is readable. The sheet is visually distinct from the app background behind it.
  - **Fail:** Sheet background is pure black and merges invisibly with the app background.

- [ ] **BUG1-3** Add one item with unitCost > 0. Return to Value by Category.
  - **Pass:** `ContentUnavailableView` is replaced by actual category data (pie chart or bar list).
  - **Fail:** Empty state still shows even with valid data, OR data shows but empty state also appears.

- [ ] **BUG1-4** Light mode, account with real category data: verify no regression — the category view still shows correct data.
  - **Pass:** Data appears correctly in light mode.

- [ ] **BUG1-5** Dark mode, account with real category data: verify cards in ValueByCategoryView use `Color(.secondarySystemGroupedBackground)` (elevated, not merged with background).
  - **Pass:** Cards are visually distinct from the page background in dark mode.

- [ ] **BUG1-6** No hardcoded `Color.gray.opacity(0.1)` or similar non-semantic color remains in ValueByCategoryView. (Code review verification or visual test with both light/dark toggle.)

---

## Bug 2 — Dead Stock / Never Audited Grace Periods

**Root cause:** Items added minutes ago appeared in "Possible dead stock" and "Never audited" Smart Insights.

### Steps

- [ ] **BUG2-1** Add a brand new item right now (within the last 5 minutes). Navigate to Dashboard. Check the Smart Insights section.
  - **Pass:** The new item does NOT appear in "Possible dead stock" or "Never audited".
  - **Fail:** The new item appears in either insight immediately after creation.

- [ ] **BUG2-2** Check an item created 3 days ago with no count history. Check "Never audited" insight.
  - **Pass:** Item does NOT appear (grace period is 7 days). Three days is within the grace window.
  - **Fail:** Item appears in "Never audited" before the 7-day grace period has elapsed.

- [ ] **BUG2-3** Check an item with `createdAt` = 8 days ago and no count history. Check "Never audited" insight.
  - **Pass:** Item DOES appear in "Never audited" (past the 7-day grace period).
  - **Fail:** Item does not appear, suggesting the 7-day filter is too aggressive or not applied.

- [ ] **BUG2-4** Check an item with `createdAt` = 20 days ago, `updatedAt` = 20 days ago (nothing changed), no count history. Check "Possible dead stock" insight.
  - **Pass:** Item does NOT appear in "Possible dead stock" (grace period requires `createdAt` < 30 days ago for dead stock).
  - **Fail:** Item appears in dead stock before the 30-day creation grace period.

- [ ] **BUG2-5** Check an item with `createdAt` = 35 days ago and `updatedAt` = 61 days ago. Check "Possible dead stock".
  - **Pass:** Item DOES appear in "Possible dead stock" (both `updatedAt` > 60 days AND `createdAt` > 30 days conditions met).
  - **Fail:** Item does not appear, suggesting either threshold is wrong.

- [ ] **BUG2-6** Verify "Never audited" does not appear if count history is non-empty, regardless of creation date.
  - **Pass:** An old item that has been counted at least once does NOT appear in "Never audited".

---

## Bug 3 — Settings Cleanup (Ad Tracking Row + API Key Row)

**Root cause:** "Privacy & Ads" section with "Ad Tracking" row, and "Anthropic API Key" row, shown to all users regardless of build type or configuration.

### Steps

- [ ] **BUG3-1** Open Settings (Dashboard → gear icon). Scroll through all sections.
  - **Pass:** NO "Privacy & Ads" section is visible. No "Ad Tracking" or "Ad Tracking Settings" row appears anywhere in Settings.
  - **Fail:** "Privacy & Ads" section or any ad tracking row is visible to a regular user.

- [ ] **BUG3-2** In a Debug build (#if DEBUG), open Settings. Confirm the "Privacy & Ads" / Ad Tracking section IS visible (debug-only visibility restored).
  - **Pass:** Debug builds show the section; Release builds do not.

- [ ] **BUG3-3** On a device where Secrets.plist contains a valid `anthropicAPIKey` value, open Settings.
  - **Pass:** "AI Features" / "Anthropic API Key" row is NOT visible (key is already configured, no need to show it).
  - **Fail:** API key row is visible even though key is in Secrets.plist.

- [ ] **BUG3-4** On a device where `SecretsManager.anthropicAPIKey == nil` (no key in Secrets.plist), open Settings.
  - **Pass:** An "AI Settings" or equivalent row IS visible (user may need to configure the key).
  - **Fail:** Row is hidden even when key is not configured.

- [ ] **BUG3-5** Verify the Settings sheet does not look cluttered or broken after removing the hidden rows. Scroll all sections — confirm no visual gaps, orphaned section headers, or empty list sections remain.
  - **Pass:** Settings layout is clean, continuous, no empty section headers.

- [ ] **BUG3-6** The ATT permission dialog still fires automatically on first app launch (removing the Settings row does not disable ATT functionality).
  - **Pass:** Fresh install → ATT prompt appears at appropriate time (first use of data). No regression in ATT behavior.

---

## Bug 4 — Currency Consistency Across Views

**Root cause:** Some views created their own `CurrencyManager()` instead of using the root `@EnvironmentObject`, causing some prices to show "$" even when currency was set to "₹".

### Steps

- [ ] **BUG4-1** Open Settings, change currency to EUR. Tap Done. Navigate to Storages → Test Warehouse (StorageDetailView).
  - **Pass:** Total value header in StorageDetailView shows "€", not "$". Item row prices show "€".
  - **Fail:** Total value shows "€" but item rows still show "$" (or vice versa) — the inconsistency bug.

- [ ] **BUG4-2** With currency = EUR, navigate to Items tab. View an item row's price in the list.
  - **Pass:** Price shows "€".
  - **Fail:** Price shows "$".

- [ ] **BUG4-3** Change currency to INR. Navigate to Dashboard → "Value by Category" (ValueByCategoryView).
  - **Pass:** Total and per-category values show "₹".
  - **Fail:** Any value shows "$".

- [ ] **BUG4-4** With currency = INR, open ItemDetailView. Check unit cost, total value, and the Profitability section (selling price, profit/unit).
  - **Pass:** All monetary values show "₹".
  - **Fail:** Any value shows "$" or "€" when not selected.

- [ ] **BUG4-5** With currency = INR, open ReportsView. Check Revenue, COGS, Profit, and Top Items revenue values.
  - **Pass:** All monetary values show "₹".
  - **Fail:** Any value shows "$".

- [ ] **BUG4-6** Code regression check: confirm no view file in `Views/` contains a hardcoded `"$"` string for currency display or a bare `String(format: "%.2f", amount)` without currency formatting. (Grep: `grep -r '"\\$"' Views/` and `grep -r '"%.2f"' Views/` — each hit must have a currency-context comment or be for non-monetary data.)
  - **Pass:** Zero unintentional hardcoded `"$"` hits; any `"%.2f"` uses are for non-monetary values only.

---

## Bug 5 — Dark Mode Card Backgrounds (StorageListView + StorageDetailView)

**Root cause:** Storage row cards used a background color identical to the page background in dark mode, making rows invisible.

### Steps

- [ ] **BUG5-1** Enable dark mode. Navigate to Storages tab (StorageListView).
  - **Pass:** Each storage card is visually distinct from the page background — there is a visible elevation difference (slightly lighter dark gray card on darker background). Cards are NOT invisible.
  - **Fail:** Cards have the same color as the page background; rows appear as flat, undifferentiated surface.

- [ ] **BUG5-2** Enable dark mode. Navigate to Storages → Test Warehouse (StorageDetailView). Scroll through item rows.
  - **Pass:** Each item row has a visually distinct background (`.secondarySystemGroupedBackground`) against the list background. Row separators or background elevation is clearly visible.
  - **Fail:** Item rows blend into the background; list appears as an undifferentiated dark surface.

- [ ] **BUG5-3** Toggle back to light mode. Confirm storage cards in StorageListView still look correct (light gray elevated cards, no regression).
  - **Pass:** Light mode appearance unchanged and correct.

- [ ] **BUG5-4** Toggle back to light mode. Confirm item rows in StorageDetailView still look correct.
  - **Pass:** Light mode appearance unchanged.

- [ ] **BUG5-5** Verify no hardcoded `Color(.systemBackground)` is used for card/row backgrounds in either `StorageListView.swift` or `StorageDetailView.swift`. Those views must use `Color(.secondarySystemGroupedBackground)` or `Color(.tertiarySystemBackground)`.
  - **Pass:** Only semantic elevated colors used for card surfaces.

- [ ] **BUG5-6** Dark mode regression — DashboardView: existing KPI cards and the new "Sales Performance" card must also be visually distinct from the Dashboard background. (Phase 7A adds new cards — confirm they also use the correct semantic background token.)
  - **Pass:** All Dashboard cards visually elevated in dark mode.

---

---

# SECTION 4: SMB Profitability Review Readiness (7/10 Target)

The `stoqly-smb-review` skill evaluates the app from the perspective of an SMB end-user (restaurant, café, shop) who has used the app for several months. The "Profitability Insights" dimension tests whether the app meaningfully answers: *"Am I making money?"*

A score of ≥ 7/10 requires ALL of the following to be present and functional. Items marked (critical) are blocking — missing them caps the score at ≤ 5.

---

## What a 7/10 Profitability Reviewer Specifically Looks For

### (1) Can I see my profit margin per item? (Critical)
- ItemDetailView Profitability section exists and shows Cost, Selling Price, Profit/unit, Margin % for any item with sellingPrice > 0.
- Margin is color-coded (green/orange/red) so the reviewer can immediately see "good" vs "bad" items without calculating.
- Items without a selling price show a CTA to set one — not a confusing blank or "0% margin".

### (2) Can I record a sale without friction? (Critical)
- "Record Sale" button is visible on ItemDetailView with one tap (no buried menu).
- QuickSaleSheet is fast: pre-fills item name, current stock, and selling price. The reviewer does not need to re-enter data they already set.
- After saving, stock deducts immediately. The reviewer can see the new stock level without refreshing or relaunching.

### (3) Can I see whether this month was profitable? (Critical)
- ReportsView (reachable in ≤ 2 taps from Dashboard) shows at minimum: total Revenue, COGS, Gross Profit, and Margin % for the current month.
- A bar chart trend shows whether revenue is growing or declining over the period.
- The reviewer does not need to open a spreadsheet to answer "what was my profit this month?".

### (4) Does the app show the right currency? (High impact)
- All prices consistently show the reviewer's local currency (₹, €, $, etc.) everywhere — Dashboard, item lists, ItemDetailView, ReportsView.
- A reviewer in India seeing "$" anywhere after setting "₹" will rate the app low on professionalism and trust.

### (5) Does the app flag low-margin items proactively? (Score booster)
- Margin Alerts in ReportsView automatically surface items with < 10% margin or items sold at a loss.
- The reviewer does not need to manually scan all items to find the "bad" ones — the app surfaces them.
- Items flagged as "Selling at a loss" in red feel like a real business intelligence tool, not just a stockroom app.

### (6) Is there a visual signal on the Dashboard? (Score booster)
- The Sales Performance section on Dashboard means the reviewer sees revenue and profit every time they open the app — even before navigating to Reports.
- Period picker lets the reviewer check "how did I do today" vs "how did I do this week" without opening a separate screen.

### (7) Are the empty states helpful? (Protects score)
- A brand new install does NOT show a confusing "No Sales This Period" on the Dashboard for a user who hasn't started using sales yet (section is hidden).
- When the reviewer first sets up an item with a selling price, the profitability section appears immediately without needing to restart.
- The "No Sales This Period" empty state in ReportsView tells the reviewer exactly what to do ("Record sales from any item") — not just a blank page.

### What Would Drop Score Below 7/10
- Selling price field does not exist in Edit Item → reviewer cannot set margins → automatic 3/10 cap.
- No Reports screen or no way to see period-based revenue → automatic 4/10 cap.
- Currency inconsistency (₹ in one view, $ in another) → -1 to -2 points.
- "Record Sale" is hard to find (buried in a menu or requires 3+ taps from ItemDetailView) → -1 point.
- Stock does not update after recording a sale (no confirmation that the workflow worked) → -1 point.
- ReportsView crashes or shows an error state on the first open → -2 points.
- Margin color coding absent (all margins look the same, no visual distinction) → -1 point.

### Pre-Ship Profitability Checklist (Run Before SMB Review)
- [ ] At least 5 items have selling prices set in the test account
- [ ] At least 10 SaleEvents across the last 30 days
- [ ] At least 2 items have margin < 10% (to verify Margin Alerts trigger)
- [ ] At least 1 item has sellingPrice < unitCost (to verify loss warning)
- [ ] Currency is set to INR for the review session (non-USD reviewer perspective)
- [ ] All 5 bug fixes applied (currency consistency is a critical visual quality signal)
- [ ] `isPro = true` is reverted to `false` to correctly test paywall gating
- [ ] ReportsView loads without error in both Today and This Month periods
- [ ] QuickSaleSheet flow completes end-to-end without crash on a real device

---

---

# APPENDIX: run_all.yaml Update Instructions

Add the following lines to `maestro/run_all.yaml` after the `# ── Smart Count flows (81–87)` block:

```yaml
# ── Phase 7A — Sales, Profitability & Reports (88–92) ─────
- runFlow: flows/88_selling_price_and_margin.yaml
- runFlow: flows/89_record_quick_sale.yaml
- runFlow: flows/90_add_inventory_movement_purchase.yaml
- runFlow: flows/91_reports_view_period_switch.yaml
- runFlow: flows/92_currency_consistency_check.yaml
```

---

## Flow Index (88–92)

| Flow # | File | What it tests |
|--------|------|---------------|
| 88 | `88_selling_price_and_margin.yaml` | Set selling price in Edit Item → live margin caption → saved margin in ItemDetailView → below-cost warning |
| 89 | `89_record_quick_sale.yaml` | Record sale from ItemDetailView → QuickSaleSheet → live profit preview → save → stock decreases → Activity Feed |
| 90 | `90_add_inventory_movement_purchase.yaml` | Add Movement sheet → IN/Purchase type → qty entry → price label → save → stock increases |
| 91 | `91_reports_view_period_switch.yaml` | Open ReportsView from Dashboard → period picker: Today/Week/Month → summary card renders → movements section → dismiss |
| 92 | `92_currency_consistency_check.yaml` | Change currency to EUR → StorageDetailView shows €, ItemDetailView shows € → no $ visible → reset to USD |

---

*End of Phase 7A QA Test Plan.*
