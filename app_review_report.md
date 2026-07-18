# Smart Inventory — Expert App Review
**Date:** April 20, 2026 | **Version:** 1.0.0 | **Reviewer:** AI Expert Assessment

---

## Summary Scorecard

| Dimension | Score | Grade |
|---|---|---|
| Visual Design & Aesthetics | 6.5 / 10 | B- |
| UX & Navigation | 5.5 / 10 | C+ |
| Feature Completeness (SMB) | 4.5 / 10 | C |
| Ease of Use & Onboarding | 6.0 / 10 | B- |
| Performance & Architecture | 7.0 / 10 | B+ |
| Data Integrity & Reliability | 6.0 / 10 | B- |
| Productivity & Efficiency | 4.5 / 10 | C |
| Search & Discoverability | 6.5 / 10 | B- |
| Monetisation & Pro Value | 5.5 / 10 | C+ |
| Stability & Polish | 4.5 / 10 | C |
| **Overall** | **5.7 / 10** | **C+** |

---

## 1. Visual Design & Aesthetics — 6.5 / 10

**What's working well:**
- Consistent use of blue as the primary accent colour. Feels professional and trustworthy.
- Cards with soft shadows and rounded corners look clean and modern.
- The coloured left-border stripe on item/storage cards is a nice differentiator — gives visual structure without being noisy.
- The donut chart on the dashboard is a great visual addition. Clean, readable, informative.
- Typography is clear: bold titles, secondary captions in grey. Hierarchy is solid.
- Status colour coding (green = In Stock, orange = Low Stock, red = Out of Stock) is intuitive and consistent.

**What needs work:**
- The always-visible red trash and blue edit circular buttons on every storage row are visually heavy and cluttered. iOS convention is swipe-to-reveal destructive actions — having them permanently visible increases accidental-delete risk and adds noise to every row.
- "5.0 units", "35.0 units" — the unnecessary decimal on whole numbers looks unpolished. Should show "5 units" not "5.0 units".
- The tab bar has 5 items all at equal weight. The icon for "Count/Audit" (clipboard) is too similar to the clipboard icon used inside StorageDetailView item rows, creating confusion.
- The dashboard header subtitle "Manage your inventory efficiently" is generic filler. Replace with something contextual (e.g., last sync time, or today's date).
- Profile screen is too sparse at the top — large empty space below the user card before "Go Pro".
- No dark mode screenshots provided to assess — dark mode support is expected by users in 2026.

---

## 2. UX & Navigation — 5.5 / 10

**What's working well:**
- The 5-tab structure covers the primary use cases.
- Category filter chips in both StorageDetailView and ItemListView are a clean pattern.
- Dashboard KPI cards are tappable and navigate contextually (at least some of them).
- Storage filter chips in the Count/Audit tab work well.
- The notification banner for low stock appeared correctly at the top of the Storages view.

**What needs work:**
- **Critical inconsistency:** Item detail opens as a bottom sheet when accessed from the Storages tab (IMG_2281), but as a full-screen view with the tab bar when accessed from the Items tab (IMG_2282, 2288). This is a jarring inconsistency — the same screen should behave the same way everywhere.
- The "Out of Stock ⊗" label with "Set to zero" button appears on the Carrot item detail (IMG_2282) even though Carrot is currently In Stock with 35 units. This is deeply confusing. A user will wonder why their in-stock item is showing an "Out of Stock" warning. This should only appear when the item IS out of stock, or should be rephrased as an action: "Mark as Out of Stock".
- Quick Count defaults to "0" as the new quantity (IMG_2290, 2291). If a user accidentally saves without entering a number, it wipes their stock to zero. This is a serious UX safety issue — default should be empty/blank or mirror the current quantity.
- The "Count" button label visible inside StorageDetailView item rows was not updated to "Audit" — inconsistency with the intended rename.
- Storage chips in the Items tab get truncated: "Kitchen (Te" is cut off (IMG_2275). Long storage names need a truncation strategy (ellipsis or max character limit on the chip).
- No swipe gestures anywhere — swipe-to-delete on list rows is a foundational iOS pattern that's missing.
- The "Count" tab and "Items" tab have conceptual overlap that confuses new users. The purpose of each tab isn't immediately obvious from the icons or names alone.

---

## 3. Feature Completeness for SMB Inventory — 4.5 / 10

**What's present:**
- Multiple storages ✓
- Items with SKU, barcode, description, category, expiry, min/max quantities, cost ✓
- Inventory Count (Quick Count + Full Count) ✓
- Low stock / out of stock status tracking ✓
- Dashboard with KPI summary ✓
- Cloud sync (Firestore) ✓
- Category filtering ✓
- Search ✓
- Push notifications for low stock ✓
- Pro tier (paywall) ✓

**What's missing for a best-in-class SMB app:**
- No stock movement log / transaction history (receiving stock in, recording stock out, transfers between storages) — the activity feed shows "No activity yet" which means it's not capturing events yet.
- No supplier management — for an SMB, knowing which supplier to reorder from is critical.
- No purchase order / reorder workflow — the Min Quantity field exists but there's no "generate reorder list" or "create PO" action.
- No barcode scanning in the UI — the field exists in Add Item but there's no camera scan button visible anywhere.
- No CSV import/export — SMBs have existing spreadsheets and need this on day one.
- No bulk operations — can't select multiple items to update, move, or delete.
- No sub-locations within a storage (e.g., Shelf A, Bin 3).
- No team/multi-user support with roles (manager vs. staff permissions).
- No reporting — no downloadable reports, no trend charts over time.
- No widget or Today extension for quick stock checks.

---

## 4. Ease of Use & Onboarding — 6.0 / 10

**What's working well:**
- Add Item form is logically sectioned: Photo → Item Info → Category → Expiry → Quantity & Pricing → Storage Location. Good flow.
- The Pro-gated photo feature has a clear inline banner that explains the value ("Helps your team identify stock instantly") and has a tappable "Pro" badge — non-intrusive.
- The Count Item form is clean and focused.
- Support flow is excellent — pre-fills email with device info, iOS version, app version, and plan type (IMG_2292). This is a pro-level detail.
- Email verification prompt in Profile is visible and actionable.

**What needs work:**
- No onboarding walkthrough beyond the initial screen. After first login, a new user lands on the Dashboard with no guidance on what to do first.
- The "Adjustment Reason" field in Count Item (IMG_2285) shows "Select reason ◊" but it's unclear what reason options exist — users don't know what to expect.
- The "Change UOM or count type" link in Quick Count (IMG_2290) is styled as a tertiary action but is important — new users may not notice it.
- "UOM" as a label without expansion ("Unit of Measure") may confuse non-technical SMB owners.
- No tooltips or contextual help anywhere in the app.
- The "Has Expiry Date" toggle in Add Item defaults to off, which is fine, but there's no hint that expiry notifications exist — users won't know to enable it.

---

## 5. Performance & Architecture — 7.0 / 10

**What's working well:**
- SwiftData + Firestore dual persistence is a well-chosen architecture: offline-first, real-time sync.
- The sync status strip ("Syncing to cloud…") at the top of the tab bar is a clean non-blocking indicator.
- @Query-driven views mean the UI reacts instantly to local data changes.
- The startup sync logic (cloud pull first, then migrate if cloud empty) is sound.
- Data isolation fix (clearLocalData on sign-out) is now in place — critical for a multi-user/multi-device scenario.

**What needs work:**
- Cannot assess actual runtime performance from screenshots — needs simulator/device testing with realistic data (100+ items, 10+ storages).
- No pagination or lazy loading strategy visible for large item lists — @Query with no limit could be slow at scale.
- The Firestore listener approach needs to be verified for cost efficiency — full collection reads on every sync can be expensive.

---

## 6. Data Integrity & Reliability — 6.0 / 10

**What's working well:**
- Min/Max quantity bounds are stored and used for low stock detection.
- Last Updated and Created timestamps are surfaced in Edit Item (IMG_2283).
- Cloud sync ensures data survives device loss.
- Sign-out now clears local SwiftData (privacy fix).

**What needs work:**
- Quick Count defaulting to 0 is a data integrity hazard — accidental saves = stock wiped.
- No audit trail / change log. Once a count is saved, there's no record of what it was before. For regulated industries or accountability, this is a gap.
- No confirmation dialog before saving a Quick Count — a single tap on Save can permanently alter stock levels.
- "Unit Cost $0.00" visible in item details (IMG_2281, 2288) — zero cost items can distort total value calculations and should be visually flagged or require explicit confirmation.
- UOM shows "N/A" in item detail even when a UOM was seemingly set — this should be investigated.

---

## 7. Productivity & Efficiency — 4.5 / 10

**What's working well:**
- Quick Count is genuinely fast — minimal taps to record a count.
- Category filters and storage filters reduce noise well.
- Multi-field search (name, SKU, barcode, description, category, storage) is strong.

**What needs work:**
- No barcode scan shortcut — for a warehouse user counting 50 items, scanning would save enormous time.
- No bulk count or batch operations.
- No swipe actions on list rows (quick delete, quick count).
- No Spotlight search integration.
- No Apple Watch companion for quick counts on the floor.
- No widgets for dashboard glanceability.
- The Count flow requires: tap Count tab → find item → tap Count → enter new quantity → Save. For high-frequency counting, this is too many taps.
- No reorder list — the app knows what's low stock but gives no "here's your shopping list" action.

---

## 8. Search & Discoverability — 6.5 / 10

**What's working well:**
- The global search icon is present on the Dashboard header.
- Category filter chips on Items and Storage Detail views are well-placed.
- Storage filter chips on Items tab allow cross-storage visibility.
- Search works across name, SKU, barcode, description, category, and storage name.

**What needs work:**
- Global search (magnifying glass on Dashboard) — could not verify it works in these screenshots. The sheet should be tested.
- No search on the Count/Audit tab (it has a local search, but not globally integrated).
- No recently searched or suggested search terms.
- Storages list search only searches storage names — should also search by items within a storage.
- No filter by date added, value range, or expiry range.

---

## 9. Monetisation & Pro Value — 5.5 / 10

**What's working well:**
- The inline photo banner (IMG_2279, 2284) is clean, non-intrusive, and explains the value clearly.
- "Upgrade to Pro" in Profile clearly lists the benefits: unlimited storages, advanced analytics, no ads.
- The Pro badge pill is visually distinct.

**What needs work:**
- "Unlimited storages" as a Pro benefit implies free users have a storage limit — but this limit is not communicated anywhere before the paywall. Free users will hit it unexpectedly.
- "Advanced analytics" is listed as a Pro benefit but there's no preview of what that looks like — users need to see what they're buying.
- "No ads" implies there are ads on the free tier — but no ads were visible. If ads aren't implemented yet, this claim is misleading.
- The paywall value proposition needs a screenshot or preview of Pro features to convert better.
- There's no free trial offer visible, which is a missed conversion opportunity.

---

## 10. Stability & Polish — 4.5 / 10

**What's working well:**
- The app didn't crash during the session shown in screenshots.
- The support email flow is excellent (device/OS info pre-filled).
- Version 1.0.0 is displayed correctly.

**What needs work:**
- The "Audit" rename did NOT take effect in this build — the tab still shows "Count", the header still says "Inventory Count", and the search placeholder still says "Search items to count..." despite Cursor marking it as completed. This is a critical miss.
- "Email not verified" warning is present but the orange text lacks enough contrast — could be missed.
- The app icon in the home screen (IMG_2268) badge shows "3" notifications — the notification pipeline is working, which is good.

---

## Bug List

| # | Bug | Severity | Screen |
|---|---|---|---|
| B1 | Tab bar still shows "Count" not "Audit" — Cursor rename did not apply to running build | Critical | All screens |
| B2 | Count tab header still says "Inventory Count" instead of "Audit" | Critical | IMG_2276, 2289 |
| B3 | Search placeholder still says "Search items to count..." instead of "audit" | High | IMG_2276, 2289 |
| B4 | Quick Count defaults to "0" — accidental save wipes stock to zero | High | IMG_2290, 2291 |
| B5 | "Out of Stock ⊗" action label shown on In Stock items (Carrot, 35 units) — confusing | High | IMG_2282 |
| B6 | Item detail opens as bottom sheet from Storages tab but full-screen from Items tab — inconsistent navigation | High | IMG_2281 vs 2288 |
| B7 | Storage chip labels truncated: "Kitchen (Te" cut off in Items tab filter row | Medium | IMG_2275 |
| B8 | UOM shows "N/A" in item detail even when UOM was set during item creation | Medium | IMG_2281, 2288 |
| B9 | "Count" button label in StorageDetailView not updated to match "Audit" rename | Medium | IMG_2278 |
| B10 | "5.0 units" / "35.0 units" — unnecessary decimal on whole-number quantities throughout | Low | Multiple |
| B11 | Edit Item form shows "Uncategorised" for Carrot even though it was created with no category change — category not being saved/loaded correctly | Low | IMG_2284 |
| B12 | Always-visible delete buttons (no swipe-to-reveal) — accidental delete risk | Medium | IMG_2274, 2277 |
| B13 | No confirmation before saving Quick Count — one tap can zero out stock | High | IMG_2290 |
| B14 | "No activity yet" in Recent Activity — activity events not being recorded despite counts being performed | Medium | IMG_2270 |

---

## Priority Fix List (in order)

1. **Rebuild and deploy the Audit rename** (B1, B2, B3) — Cursor's changes didn't make it into the running build.
2. **Quick Count blank default + save confirmation** (B4, B13) — data integrity risk.
3. **"Out of Stock" label on in-stock items** (B5) — rename to "Mark as Out of Stock" and only show when appropriate.
4. **Item detail navigation consistency** (B6) — pick one pattern and apply everywhere.
5. **Activity feed not logging events** (B14) — the feed is the most important engagement feature on the Dashboard.
6. **UOM N/A** (B8) — investigate why UOM is not persisting to the detail view.
7. **Storage chip truncation** (B7) — apply `lineLimit(1)` + `fixedSize` or max width constraint.

---

*Report generated: April 20, 2026*
