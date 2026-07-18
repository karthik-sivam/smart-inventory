# Phase 7A — Manual Device Quick-Test Checklist

Run these on a **physical device** with **existing inventory data** (not a fresh install).
Check each box when it passes. Flag any failure with a one-line note.

---

## 1. Selling Price & Margin

- [ ] Open any item → Edit → "Selling Price" field appears below "Unit Cost"
- [ ] Enter a selling price → margin % updates live (e.g. cost ₹100, price ₹130 → "23% margin")
- [ ] Margin colour: >30% green, 10–30% orange, <10% red
- [ ] Save → ItemDetailView shows Profitability section with cost / price / margin
- [ ] Set selling price to 0 → margin shows "—" or "No price set" (not NaN/crash)
- [ ] Selling price persists after app restart

## 2. Quick Sale

- [ ] StorageDetailView → swipe item left → "Sale" action appears (green)
- [ ] Tap Sale → QuickSaleSheet opens with item pre-filled
- [ ] Quantity defaults to 1; enter 3 → revenue and profit update
- [ ] Confirm sale → item quantity decreases by 3
- [ ] ActivityEvent "SaleMade" appears in activity feed on Dashboard
- [ ] Currency symbol consistent with Settings (no $ vs ₹ mismatch)
- [ ] Selling below cost → gross profit shows negative (red)
- [ ] Try selling more than available stock → graceful error (no crash)

## 3. Inventory Movements

- [ ] ItemDetailView → "Add Movement" → MovementSheet opens
- [ ] Select "Purchase (IN)" → enter qty 10 → confirm → stock increases
- [ ] Select "Adjustment (OUT)" → stock decreases
- [ ] ActivityEvent "MovementLogged" appears in feed
- [ ] MovementsListView (accessible from Reports) → shows all movements with type, qty, date

## 4. Reports View

- [ ] Dashboard → "Sales Performance" section appears below KPI cards
- [ ] "View Full Report →" → ReportsView opens as sheet
- [ ] Period tabs: Today / This Week / This Month / Custom (Pro-gated)
- [ ] Revenue and Units Sold update when period changes
- [ ] Revenue trend chart renders (no empty chart)
- [ ] Top Items by Revenue section shows items sold
- [ ] Gross Profit and margin % show correctly
- [ ] Close sheet → back to Dashboard cleanly (no navigation stack corruption)

## 5. KPI Cards (Dashboard)

- [ ] "Revenue" card appears in KPI grid (replaced "Total Storages")
- [ ] "Gross Profit" card appears (replaced "Total Items")
- [ ] Both default to "This Week" data
- [ ] Switch period in Sales Performance section → both KPI cards update to match
- [ ] Revenue KPI delta shows "vs last week"
- [ ] Gross Profit KPI delta shows margin % with colour coding

## 6. Currency Consistency

- [ ] Settings → Currency → change to USD → all prices show $ throughout (Dashboard, StorageDetailView, ItemDetailView, Reports)
- [ ] Change back to INR → all show ₹
- [ ] No screen shows a different currency symbol than what's set in Settings
- [ ] ValueByCategoryView shows correct currency symbol

## 7. Bug Fixes — Regression Check

- [ ] **Dead stock grace period**: add a brand-new item → does NOT appear in "Possible dead stock" on Dashboard
- [ ] **Never audited grace period**: new item → does NOT appear in "Never audited" within first 7 days
- [ ] **ValueByCategoryView**: open from Dashboard → no blank sheet with floating "Total ₹0.00"; empty state shows icon + message when no items have cost
- [ ] **Dark mode**: StorageListView rows visible (not black on black)
- [ ] **Dark mode**: StorageDetailView item rows visible
- [ ] **Settings**: "Privacy & Ads" section NOT visible in Release build (only in Debug)
- [ ] **Settings**: "AI Features" section hidden when API key is configured via Secrets.plist

## 8. Edge Cases

- [ ] No sales recorded yet → ReportsView shows empty state with CTA (not a crash or blank screen)
- [ ] Record sale for item with no selling price set → graceful handling
- [ ] Open Reports with date range that has zero sales → empty state
- [ ] Rotate device to landscape → QuickSaleSheet renders correctly

---

## After testing:
Update `automation_results.rtf` with:
- Date tested
- Device + iOS version
- Any failures found (file bug report with exact reproduction steps)
- Overall pass/fail for Phase 7A
