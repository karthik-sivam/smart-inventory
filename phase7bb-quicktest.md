# Phase 7B-B — Manual Device Quick-Test Checklist

Run on a **physical device** (Pro mode enabled for full AI feature coverage).
Check each box when it passes. Flag failures with a one-line note.

---

## 1. SmartSalesEntryView — Entry Point & Layout

- [ ] From Sales tab (non-empty state) → tap sparkles ✦ toolbar button → SmartSalesEntryView opens as a sheet
- [ ] From Sales tab (empty state) → tap "Smart Sales Entry" link → same sheet opens
- [ ] Sheet shows 5 mode cards: **Voice**, **Photo**, **Text**, **CSV / Excel**, **PDF**
- [ ] Each card has an icon, title, and short description
- [ ] All 5 cards show a "Pro" badge (since all modes are Pro-only)
- [ ] Sheet has a dismiss / Cancel button that closes it cleanly

---

## 2. Pro Gate — Free User Behaviour

*(Temporarily toggle `isPro = false` in SubscriptionManager to verify gating, then restore `true`)*

- [ ] With `isPro = false`, tap any mode card → PaywallView opens (not the mode screen)
- [ ] Dismiss PaywallView → back to SmartSalesEntryView (no crash, no stuck sheet)
- [ ] With `isPro = true`, tap any mode card → mode screen opens normally

---

## 3. Voice Mode (SmartSalesVoiceView)

- [ ] Tap Voice card → SmartSalesVoiceView opens
- [ ] Initial state shows a microphone button and "Tap to record" instruction
- [ ] Tap record → microphone activates (system permission prompt if first time)
- [ ] Speak sale details (e.g., "Sold 3 bottles of water at ₹20 each") → stop recording
- [ ] View transitions to "Analysing…" / loading state while AI processes
- [ ] On completion → SaleEntryReviewView opens with parsed rows
- [ ] If AI fails → error state shown with retry option (don't crash)

---

## 4. Photo Mode (SmartSalesPhotoView)

- [ ] Tap Photo card → SmartSalesPhotoView opens
- [ ] Options to take photo or choose from library
- [ ] Select/capture a receipt or handwritten list image
- [ ] View shows "Analysing…" state while AI processes
- [ ] On completion → SaleEntryReviewView opens with parsed rows
- [ ] If no items recognised → shows an empty review or error message (not a crash)

---

## 5. Text Mode (SmartSalesTextView)

- [ ] Tap Text card → SmartSalesTextView opens
- [ ] TextEditor is focusable and accepts multiline input
- [ ] Type sale details (e.g., "Milk x5 @₹30, Eggs x12 @₹8") → tap Parse / Submit
- [ ] Shows loading/analysing state
- [ ] On completion → SaleEntryReviewView with parsed rows
- [ ] Empty submission → shows validation message (not a crash)

---

## 6. CSV / Excel Mode (SmartSalesCSVView)

- [ ] Tap CSV/Excel card → SmartSalesCSVView opens with file picker
- [ ] Pick a `.csv` file → view parses and shows SaleEntryReviewView
- [ ] Pick a `.xlsx` file → view parses (uses shared XLSXParser) and shows SaleEntryReviewView
- [ ] BulkImportView still works correctly (regression check — XLSXParser extraction)

---

## 7. PDF Mode (SmartSalesPDFView)

- [ ] Tap PDF card → SmartSalesPDFView opens with file picker
- [ ] Pick a PDF receipt → view rasterises pages and sends to AI
- [ ] Multi-page PDF (>10 pages) → only first 10 pages processed (check no crash on large PDF)
- [ ] On completion → SaleEntryReviewView with parsed rows

---

## 8. SaleEntryReviewView — Core Behaviour

Run this section after getting to the review screen from any mode above:

- [ ] Review screen shows a list of `ParsedSaleRow` items with item name, qty, price per unit
- [ ] Items that matched an existing inventory item show the matched item name (linked)
- [ ] Unresolved items show a "Link item" or picker option (not a crash)
- [ ] Tap a row's item picker → SaleItemPickerSheet opens; selecting an item links it and dismisses
- [ ] "Skip" toggle on a row → item excluded from final save
- [ ] Tap **Confirm / Save** → all non-skipped rows save as SaleEvents
- [ ] A single `safeSave` is used (no crash, no duplicate records)
- [ ] After save → sheet dismisses and Sales tab list shows the new entries
- [ ] Confirmed sales appear in Firestore (check Firebase console or re-launch app to verify sync)
- [ ] Currency formatting in review rows matches device currency setting (no hardcoded $)

---

## 9. SaleEntryReviewView — Edge Cases

- [ ] All rows skipped → Confirm does nothing or shows "Nothing to save" (no crash, no empty SaleEvent)
- [ ] One row has `item: nil` (unresolved) and is NOT skipped → saves with `itemName` from parsed text, `item` relationship nil (no crash)
- [ ] Review screen with 0 parsed rows → shows empty state, not a crash
- [ ] Cancel from review → no records saved, back to SmartSalesEntryView or Sales tab

---

## 10. Purchase Invoice Import (PurchaseInvoiceImportView)

- [ ] Open StorageDetailView for any storage → toolbar or item action shows "Import Invoice" button
- [ ] Tap Import Invoice → PurchaseInvoiceImportView opens
- [ ] Pick a supplier invoice (PDF or photo) → AI parses into PurchaseReviewView rows
- [ ] PurchaseReviewView shows: item name, quantity, price per unit (purchase price)
- [ ] Items matched to existing inventory items show their names
- [ ] Tap Confirm → InventoryMovement (IN) records created for each matched row
- [ ] `lastPurchasePrice` and `lastPurchasedAt` updated on matched InventoryItem records
- [ ] Single `safeSave` after batch (no per-row saves)
- [ ] Unmatched items handled gracefully (skipped or saved with `item: nil`)
- [ ] Confirm → sheet dismisses, StorageDetailView reflects updated stock quantities

---

## 11. Analytics Events

*(Check Amplitude dashboard or add a temporary `print` to verify events fire — remove prints before shipping)*

- [ ] Opening SmartSalesEntryView fires `smartSalesOpened`
- [ ] Selecting a mode fires `smartSalesModeSelected` with mode name
- [ ] Completing a session (saving from review) fires `smartSalesCompleted`

---

## 12. Regression — Existing Sales Flows

- [ ] QuickSaleSheet still works from StorageDetailView swipe action
- [ ] Record Sale button in ItemDetailView still opens QuickSaleSheet
- [ ] SaleItemPickerSheet + QuickSaleSheet from Sales tab + button still works
- [ ] ReportsView "Record a Sale" CTA still works (notification flow)
- [ ] BulkImportView (CSV/Excel import for inventory items) still works end-to-end

---

## 13. Maestro Regression (if running simulator tests)

- [ ] Flow 88: Sales empty state navigation passes
- [ ] Flow 89: Item picker from sales tab passes
- [ ] Flow 90: Smart Sales Pro gate passes (free user sees paywall)
- [ ] Existing flows 1–87 still pass (`maestro test maestro/run_all.yaml`)

---

## After Testing

Update `automation_results.rtf` with:
- Date tested
- Device + iOS version
- Any failures (with exact reproduction steps)
- Overall pass/fail for Phase 7B-B

If all passes → next step is **M6** (reorder email grouping, offline write queue, daily summary notification, cost layer).
