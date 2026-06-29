# Phase 7B-A — Manual Device Quick-Test Checklist

Run on a **physical device** with existing data. Check each box when it passes.
Flag failures with a one-line note.

---

## 1. Tab Bar Restructure

- [ ] App opens → bottom tab bar shows: Dashboard | Storages | Items | Sales | Audit (5 tabs, in this order)
- [ ] No "Profile" tab in the bar (it was removed)
- [ ] Dashboard tab has a gear icon (⚙️) in the toolbar (top-right or top-left)
- [ ] Tap gear icon → ProfileView opens as a sheet (not a full nav push)
- [ ] ProfileView has a "Done" or dismiss button that closes it
- [ ] Settings is accessible from within ProfileView (gear row inside profile)
- [ ] Audit tab is index 4 (tapping it shows the count/audit workflow)

---

## 2. Sales Tab — Empty State

- [ ] Tap Sales tab (index 3) with zero sales recorded → empty state shows (not a blank screen)
- [ ] Empty state has an icon, a title, and at least one CTA button ("Record a Sale" or similar)
- [ ] "Record a Sale" button on empty state → SaleItemPickerSheet opens
- [ ] "Smart Sales Entry" button visible on empty state (shows "Coming Soon" stub — Phase 7B-B)

---

## 3. SaleItemPickerSheet

- [ ] SaleItemPickerSheet shows a searchable list of all items across all storages
- [ ] Type in the search bar → list filters instantly
- [ ] Tap an item → picker dismisses and QuickSaleSheet opens for that item (within ~50ms delay, no double-sheet flash)
- [ ] Cancel / swipe down picker → returns to SalesView cleanly (no crash)
- [ ] Items with no selling price set → still appear in picker (not hidden)

---

## 4. Sales Tab — Non-Empty State

Record at least 2–3 sales on different dates first, then:

- [ ] Sales tab shows a grouped list (sections by date: "Today", "Yesterday", or actual dates)
- [ ] Each sale row shows item name, quantity, revenue amount, and time
- [ ] Currency symbol matches Settings (no hardcoded $)
- [ ] Toolbar shows: sparkles icon (Smart Sales Entry) + "Reports" link + plus (+) button
- [ ] Tap plus (+) → SaleItemPickerSheet opens
- [ ] Tap "Reports" → ReportsView opens

---

## 5. DatePicker Cap (Backdate Prevention)

- [ ] Open QuickSaleSheet (via Sales tab or swipe on item in StorageDetailView)
- [ ] DatePicker is present — try to select a future date → future dates are greyed out / unselectable
- [ ] Today is selectable
- [ ] Yesterday is selectable (backdating works)
- [ ] Confirmed sale uses the selected date, not today's date (check activity feed timestamp)

- [ ] Open MovementSheet (via ItemDetailView → Add Movement)
- [ ] Same check: future dates greyed out, past dates selectable

---

## 6. ReportsView Empty State CTA

- [ ] Open ReportsView with zero sales → empty state shown
- [ ] Empty state has a "Record a Sale" CTA button
- [ ] Tap it → ReportsView sheet dismisses AND SalesView opens SaleItemPickerSheet automatically (via NSNotification)
- [ ] The notification flow works without crashing (no double-open, no stuck sheet)

---

## 7. Navigation Regression Check

- [ ] Dashboard → gear → ProfileView → Settings → back to ProfileView → Done → back to Dashboard (no nav stack corruption)
- [ ] Switch between all 5 tabs rapidly → no crashes
- [ ] Sales tab → open QuickSaleSheet → cancel → back to Sales tab cleanly
- [ ] From Sales, navigate to Reports → dismiss → back to Sales (not stuck on Reports)
- [ ] Deep path: Dashboard → Sales Performance "View Full Report →" → ReportsView → "Record a Sale" CTA → SaleItemPickerSheet → item → QuickSaleSheet → confirm → back to SalesView with new sale listed

---

## 8. Maestro Regression (if running simulator tests)

- [ ] Audit flow still works (now tag 4, not tag 3)
- [ ] Profile access via Dashboard gear button (not via old tab)
- [ ] Settings access via Profile sheet (not direct tab)
- [ ] Cross-tab flows still navigate correctly

---

## After Testing

Update `automation_results.rtf` with:
- Date tested
- Device + iOS version
- Any failures (file with exact reproduction steps)
- Overall pass/fail for Phase 7B-A

If all passes → next step is **Phase 7B-B** (SmartSalesEntryView AI modes + Purchase Invoice Import).
