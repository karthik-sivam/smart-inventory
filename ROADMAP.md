# Smart Inventory — Product Roadmap
*Last updated: April 20, 2026*

---

## Phase Overview

| Phase | Theme | Goal |
|---|---|---|
| Phase 1 | Foundation ✅ | Core CRUD, cloud sync, categories, photos, global search, Maestro baseline |
| **Phase 2** | **Fix the Pain** | Ratings below 5.5 → 8. Critical bugs + missing fundamentals. |
| **Phase 3** | **Elevate the Experience** | Ratings 5.5+ → 8. Polish, onboarding, dark mode, search, flow tests. |
| Phase 4 | Power User Layer | Stock movement log, supplier management, purchase orders, CSV import, sub-locations. |
| Phase 5 | Scale & Monetise | Team roles, API access, advanced analytics, widget, Apple Watch, Pro tier expansion. |

---

---

# PHASE 2 — Fix the Pain
**Target: All dimensions below 5.5 reach 8. All existing bugs resolved.**
**Affected scores: Feature Completeness (4.5), Productivity (4.5), Stability & Polish (4.5), UX & Navigation (5.5)**

---

## 2.1 — Bug Fixes (Non-Rebuild)

These bugs were identified in the app review and require code changes (not just a rebuild).

---

### BUG B4 + B13 — Quick Count: Dangerous Default + No Confirmation

**Problem:** Quick Count defaults to "0". If a user taps Save without entering a value, stock is wiped to zero. There is also no confirmation dialog before saving.

**Fix — CountViewModel / QuickCountView:**

Step 1 — Change default new quantity from `0` to empty string (`""`). The numeric display should show a placeholder "Enter qty" in grey until the user types.

Step 2 — In `QuickCountView`, add a `.disabled` state on the Save button: disabled when `newQuantityText` is empty or unchanged from current quantity.

Step 3 — Add a confirmation alert when the new quantity is more than 50% different from current quantity (large swings are likely errors):
```
"Are you sure?"
"You're changing [Item Name] from [X] to [Y] units. This cannot be undone."
[Cancel] [Save Count]
```

Step 4 — Add a small "+/-" toggle below the quantity field. When in adjustment mode, the field shows the delta (e.g., "+10" or "-3") instead of the absolute quantity. Label changes to "Adjustment (+/-)" vs "New Quantity". This is how professional inventory tools work — warehouse staff count differences, not totals.

Design note: The +/- toggle should be a segmented control: `[ New Qty | Adjustment ]`. Default to "New Qty" for new users. Remember the user's last choice in UserDefaults.

---

### BUG B5 — "Out of Stock" Action Visible on In-Stock Items

**Problem:** In Item Detail, the `⊗ Out of Stock` label with `Set to zero` button appears regardless of current stock status. On the Carrot item (35 units, In Stock), this is deeply confusing — users think their item IS out of stock.

**Fix — ItemDetailView:**

Replace the static "Out of Stock / Set to zero" row with a context-aware `QuickActionsRow`:

```
if item.isOutOfStock {
    // Show: "⊗ Out of Stock" label (red, informational only)
    // Action: "Receive Stock" button → opens Quick Count in adjustment mode
} else if item.isLowStock {
    // Show: "⚠ Low Stock" label (orange, informational only)
    // Action: "Reorder" button (Phase 4) + "Adjust Count" button
} else {
    // Show nothing — item is healthy, no action needed
}
```

Also add a universal "Adjust Stock" button in the header action area (next to edit/delete) that opens Quick Count directly. This gives access regardless of stock status without the confusing warning labels.

---

### BUG B6 — Item Detail Navigation Inconsistency

**Problem:** Item detail opens as a bottom sheet from the Storages tab but as a full-screen view with tab bar from the Items tab. Same content, different container — jarring.

**Fix:** Standardise on full-screen modal (`.fullScreenCover` or `NavigationLink`) everywhere. The tab bar should be hidden when in item detail. Apply `.navigationBarHidden(true)` + custom back button on the detail view header consistently.

If the Storages tab uses `.sheet`, change it to match Items tab. The decision: use `NavigationLink` push from both tabs so the back navigation is consistent and the tab bar remains accessible at depth. Do not use `.sheet` for item detail — sheets imply temporary/form content, but item detail is a primary view.

---

### BUG B7 — Storage Chip Truncation in Items Tab

**Problem:** "Kitchen (Test)" truncates to "Kitchen (Te" in the storage filter chip row.

**Fix — ItemListView storage filter chips:**

```swift
ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: 8) {
        // chips
    }
    .padding(.horizontal)
}
```

Each chip's text should use `.lineLimit(1)` and a `maxWidth` cap of `120`. For names longer than 15 characters, truncate with `…` using `.truncationMode(.middle)` so both start and end of the name remain visible: "Kitchen (T...st)". Do NOT wrap chips to two lines.

---

### BUG B8 — UOM Shows N/A in Item Detail

**Problem:** Item detail shows `UOM: N/A` even for items where a UOM was set in Add Item form.

**Investigation needed:** Check `InventoryItem.uom` relationship. The UOM is stored as a relationship to a `UOM` model object. Verify that the `uom` relationship is being loaded in the detail query, and that `modelContext.fetch` includes the UOM. The most likely cause: the UOM object is being deleted or its relationship is not being preserved through Firestore sync round-trips.

**Fix:** In `FirestoreManager.pullFromCloud()`, verify that when an InventoryItem is reconstructed from Firestore data, the `uom` field (stored as a string symbol like "pcs") is correctly resolved back to a `UOM` object from the local SwiftData store. If no matching UOM exists locally, create one rather than leaving the relationship nil.

Also: in Item Detail, if `item.uom == nil`, display the raw `uomSymbol` string from Firestore data as a fallback rather than "N/A".

---

### BUG B10 — Unnecessary Decimal Places on Whole Numbers

**Problem:** "5.0 units", "35.0 units", "5.0" throughout the app. Looks unpolished.

**Fix:** Create a global extension:

```swift
extension Double {
    var smartFormatted: String {
        if self == self.rounded() && !self.isInfinite {
            return String(format: "%.0f", self)
        }
        // For fractional values (e.g. 2.5 kg), show up to 2 decimal places
        return String(format: "%.2f", self).trimmingCharacters(in: .init(charactersIn: "0"))
            .trimmingCharacters(in: .init(charactersIn: "."))
    }
}
```

Apply `item.currentQuantity.smartFormatted` everywhere a quantity is displayed. This fixes the issue for whole numbers while preserving precision for legitimate fractional quantities (e.g., 2.5 kg of flour).

---

### BUG B12 — Always-Visible Delete Buttons

**Problem:** Red trash and blue edit circle buttons are permanently visible on every Storage and Item row. This is visually cluttered, not standard iOS, and risks accidental deletes.

**Fix:** Replace with swipe-to-reveal actions using `.swipeActions`:

```swift
.swipeActions(edge: .trailing, allowsFullSwipe: false) {
    Button(role: .destructive) {
        // delete action
    } label: {
        Label("Delete", systemImage: "trash")
    }
}
.swipeActions(edge: .leading, allowsFullSwipe: true) {
    Button {
        // edit action
    } label: {
        Label("Edit", systemImage: "pencil")
    }
    .tint(.blue)
}
```

Apply to: StorageListView rows, ItemListView rows, StorageDetailView item rows.

The tap target for viewing detail remains the full card. Edit and Delete move to swipe. This frees up enormous visual space and makes the UI feel premium.

---

### BUG B14 — Activity Feed Records Nothing

**Problem:** The Recent Activity section on the Dashboard shows "No activity yet" even after performing multiple counts and edits. `ActivityEvent` model exists but is never populated.

**Fix:** Identify every user action that should generate an activity event and ensure `ActivityEvent` is inserted after each one:

- Item count saved → `ActivityEvent(type: .countRecorded, itemId:, delta:, notes:)`
- Item added → `ActivityEvent(type: .itemAdded, itemId:, storageName:)`
- Item deleted → `ActivityEvent(type: .itemDeleted, itemName:)`
- Stock set to zero → `ActivityEvent(type: .setToZero, itemId:)`
- Item edited (quantity changed) → `ActivityEvent(type: .quantityUpdated, itemId:, delta:)`

**Activity Feed Row Design:**

```
[ Icon ]  Item Name                          +15 units
          Storage Name  •  2 min ago
```

Icon colour codes: green arrow up = stock added, red arrow down = stock reduced, orange = set to zero, blue clipboard = count recorded, grey pencil = item edited.

Show last 20 events on Dashboard. "View All" navigates to a dedicated history screen (Phase 4 full activity log).

Sync `ActivityEvent` records to Firestore under `users/{uid}/activity/{id}`.

---

## 2.2 — Barcode Scanner UI

**Current state:** Barcode and SKU fields exist in Add/Edit Item but there is no camera scan button. Users must type barcodes manually.

**Target:** One-tap scan from Add Item, Edit Item, and a standalone "Scan to Find" shortcut.

**Implementation:**

Step 1 — Add a scan button inside the Barcode field in `AddItemView` / `EditItemView`:
```
[ 📷 ] Barcode (Optional) ________________
```
The camera icon on the left is a `Button` that presents `BarcodeScannerView` as a `.sheet`.

Step 2 — `BarcodeScannerView` already exists in the codebase. Wire it up: on successful scan, dismiss the sheet and populate the `barcode` text field.

Step 3 — Add a "Scan to Find Item" button on the Items tab header (next to the + button). Scanning a barcode searches `items.first(where: { $0.barcode == scannedCode })`. If found, navigate directly to that item's detail. If not found, offer "Add New Item" pre-filled with the scanned barcode.

Design: Use the system `barcode.viewfinder` SF Symbol for the scan button. The scanner overlay should show a rectangular viewfinder with animated scan line (standard pattern).

---

## 2.3 — Audit Tab vs Items Tab: Clear Purpose Differentiation

**Problem:** Users don't understand the difference between Items and Audit. They look like duplicate functionality.

**Solution — Redesign the Audit tab purpose and header:**

The Audit tab is not a list of items — it is a **counting session interface**. Rename the mental model:

**Header redesign:**
```
Audit                              [ Start Session ]
Last audit: 3 days ago  •  2 items pending

[ All Storages ] [ Low Stock Test Storage ] [ Kitchen (Test) ]
```

Add a "Last audited" timestamp per item. Items that haven't been counted in > 7 days show a subtle "Due" badge.

Items in the Audit tab should be sorted by: Out of Stock first → Low Stock → Due for audit → In Stock. This makes it a prioritised work queue, not just a flat list.

The `Count` button label on each row should become `Audit` (the rename Cursor was supposed to apply).

This gives the tab a clear, distinct purpose: **"Here is your work queue for keeping stock numbers accurate."** Items tab is **"Here is your catalogue."**

---

## 2.4 — Reorder List (Low Stock Action Hub)

**Problem:** The app tells you what's low stock but gives you nothing to do about it. SMBs need a "what do I need to buy?" answer fast.

**Implementation:**

Add a "Reorder" view accessible from the Dashboard "Low Stock Items" KPI card tap (currently it presumably navigates somewhere generic).

**Reorder List design:**
```
Reorder List                              [ Export ]
3 items need restocking

[ Low Stock Item ]
  Current: 5 units  •  Min: 10  •  Need: 5+
  Stationery & Office  •  Low Stock Test Storage
  
[ Item 2 ]
  Current: 0  •  Min: 20  •  Need: 20+
  Out of Stock
```

Each row shows: item name, current vs minimum, how many units short, storage, category. An "Export" button (Phase 4 CSV) placeholder can be shown as disabled for now.

This view is read-only for Phase 2. In Phase 4, it becomes the foundation for purchase orders.

**Implementation file:** Create `AITest/Views/ReorderListView.swift`. Wire the Dashboard "Low Stock Items" card tap to navigate to it.

---

## 2.5 — Item Detail: Consistent Full-Screen Pattern + Information Hierarchy Fix

**In addition to B6 (navigation consistency), improve the Item Detail content:**

Current information hierarchy issues:
- "Out of Stock / Set to zero" appears before Item Details (B5 fix above)
- UOM shows N/A (B8 fix above)
- No category shown in detail view
- No photo shown in detail view (even if Pro user has one)
- "N/A" for Description, Barcode looks sloppy — use `—` (em dash) instead, or hide the row entirely

**Redesigned Item Detail sections:**

```
[ Photo — full width if exists, placeholder if not ]

[ Item Name ]
  SKU: SKU-ABC  •  Category Badge  •  Stock Status Badge

[ Stats Row ]
  Current: 35  |  Status: In Stock  |  Value: $1,750

[ Quick Actions ]
  [ Adjust Stock ]  [ Audit Item ]  [ Transfer ] (Phase 4)

[ Item Details ]  (collapse rows with nil values)
  Storage: Kitchen (Test)
  UOM: Pieces (pcs)
  Min / Max: 20 / 2,000
  Unit Cost: $50.00
  Expiry: Apr 23, 2026  (only if set)

[ Recent Activity ]  (last 3 events for this item)
  Apr 20 — Count recorded: 35 units
  Apr 5 — Item created
```

---

## Phase 2 Acceptance Criteria

- [ ] Quick Count never defaults to 0; Save is disabled on empty; large-change confirmation alert shown
- [ ] Quick Count has New Qty / Adjustment toggle
- [ ] Item detail shows contextual stock status (no "Out of Stock" label on healthy items)
- [ ] Item detail opens full-screen via NavigationLink from both Storages and Items tabs
- [ ] Swipe-to-reveal edit and delete on all list rows (StorageList, ItemList, StorageDetail)
- [ ] No permanent red/blue action buttons visible on rows
- [ ] Storage chips in Items tab truncate with middle ellipsis, no overflow
- [ ] UOM displays correctly in Item Detail for all items
- [ ] All quantity displays use smart formatting (no unnecessary .0)
- [ ] Activity feed logs all count, add, delete, edit-quantity events
- [ ] Activity feed rows show icon, item name, delta, storage, time
- [ ] Barcode scan button present in Add Item and Edit Item forms
- [ ] "Scan to Find" button in Items tab header
- [ ] Dashboard Low Stock card taps to Reorder List
- [ ] Reorder List shows all items below min quantity with deficit calculation
- [ ] Audit tab shows "Last audited" per item, sorted by priority (OOS → Low → Due → OK)
- [ ] Audit tab header shows last audit date and pending count
- [ ] Build: 0 errors, 0 warnings
- [ ] Maestro: all Phase 1 flows still pass after changes

---

---

# PHASE 3 — Elevate the Experience
**Target: All dimensions at 5.5+ reach 8. Complete Maestro regression. Zero obvious bugs.**
**Affected scores: Visual Design (6.5), Ease of Use (6.0), Data Integrity (6.0), Search (6.5), Performance (7.0), Monetisation (5.5)**

---

## 3.1 — Visual Design: Dark Mode + Quantity Formatting

**Dark mode (non-negotiable for 2026):**

All views must use adaptive system colours — no hardcoded `Color.white` or `Color(.systemBackground)` with incompatible overlays. Test every screen in both light and dark.

Key areas to audit:
- Card backgrounds: use `Color(.secondarySystemGroupedBackground)` not `.white`
- Left-border accent strips on cards: verify they remain visible in dark mode
- The donut chart slice colours: ensure sufficient contrast in dark mode
- Status colour badges (green/orange/red): use `.secondary` variants where appropriate
- Tab bar background: use `Color(.systemBackground)` which is already adaptive
- The sync status strip (blue): verify white text contrast passes WCAG AA in both modes

Design tip: Use `@Environment(\.colorScheme)` only when you need to switch assets (e.g., logo). Prefer system semantic colours for everything else.

**Smart decimal formatting:**
Apply the `Double.smartFormatted` extension from Phase 2 consistently to every remaining display site. Audit: dashboard KPI numbers, storage detail stat cards, item detail stats, count history records.

---

## 3.2 — Onboarding: Post-Login Guided Flow

**Problem:** After first sign-in, a new user lands on an empty Dashboard with no direction. The guided empty state in StorageListView is good, but a user doesn't know to go there first.

**Implementation: InteractiveOnboardingFlow (shown once after first successful login)**

A 3-step full-screen modal shown only when `storages.isEmpty && !UserDefaults.hasCompletedOnboarding`:

**Step 1 — Welcome**
```
[ Large archivebox.fill icon, animated scale-in ]
Welcome to Smart Inventory
The easiest way to track what you have,
where it is, and when you're running low.

[ Get Started → ]
```

**Step 2 — Create Your First Storage**
Inline mini-form (name only, colour picker):
```
[ archivebox icon ]
Where do you store things?
A storage is a physical location — a warehouse,
a stockroom, a shelf, a fridge.

Storage Name: [________________]
Colour: ● ● ● ● ●

[ Create Storage → ] or [ Skip ]
```
If they fill it in and tap Create: create the Storage and proceed. Skip is always available.

**Step 3 — You're Ready**
```
[ checkmark.seal.fill icon, green ]
You're all set.
Tap + to add your first item to [Storage Name],
or import from a spreadsheet (coming soon).

[ Go to Dashboard ]
```

This replaces the cold-start confusion with a warm guided entry.

---

## 3.3 — Empty States: Illustrations and Context

Every empty state in the app should tell the user exactly what to do next. Current states are functional but generic.

**StorageListView empty (already improved in Phase 1 — verify it's complete):**
Confirm: gradient icon, "Welcome to Smart Inventory" headline, "Create Your First Storage" CTA, 3 hint rows.

**ItemListView empty (all storages filter active):**
```
[ cube.box.fill icon, large, tinted ]
No items yet
Add your first item using the + button above,
or tap into a storage to add items there.
[ + Add Item ]
```

**StorageDetailView empty (no items in this storage):**
```
[ tray.fill icon ]
[Storage Name] is empty
Tap + to add your first item here.
[ + Add Item ]
```

**Audit tab empty:**
```
[ checkmark.shield.fill icon, green ]
All caught up!
Every item has been counted recently.
Nothing needs auditing right now.
```

**Recent Activity empty (on Dashboard):**
```
[ clock.arrow.circlepath icon, grey ]
No activity yet
Activity appears here as you add items
and record counts.
```
(Replace "Add items and record counts to see your activity here" — the current text is clunky.)

**Search empty state (no results):**
```
[ magnifyingglass icon ]
No results for "[search term]"
Try a different name, SKU, or barcode.
```

---

## 3.4 — Dashboard Improvements

**Header:**
Replace subtitle "Manage your inventory efficiently" with a dynamic line:
- If last synced < 1 min ago: "Synced just now"
- If synced 1–60 min ago: "Synced 23 minutes ago"
- If not synced: "Offline — last synced Apr 19"
- Show a small cloud icon (`.cloudArrowUp.fill` / `.cloudArrowDown.fill`) next to it

**KPI Cards — Trend Indicators:**
Each KPI card should show a subtle trend vs 7 days ago (stored in `ActivityEvent` history):
```
  2          ↑ from 1
  Total Storages
```
Use SF Symbol `arrow.up.right` in green for increases, `arrow.down.right` in red for decreases (only on Total Items and Total Value). Low Stock and Out of Stock: inverse — going up is bad (show red arrow up), going down is good (show green arrow down).

For Phase 3, compute this from ActivityEvent records. If insufficient history, hide the trend indicator rather than showing 0%.

**Total Value card:**
Display the currency symbol correctly for non-USD users (already have CurrencyManager — verify it's applied to this card).

**Donut chart legend:**
Add total count in the centre label below the number. Currently shows "2 items" — change to:
```
  2
items
```
in the centre. The word "items" should be smaller/secondary. Clean up the centre label spacing.

---

## 3.5 — Ease of Use: Forms + Labels

**UOM label:** Change "UOM" label in Add/Edit Item to "Unit of Measure (UOM)" with "UOM" as a smaller secondary label. Users who don't know the acronym will understand immediately.

**Adjustment Reason picker:** Replace "Select reason ◊" with a proper options sheet. Reasons:
- Physical Count
- Damage / Write-off
- Theft / Shrinkage
- Supplier Correction
- Transfer (Phase 4)
- Other (with free-text note)

Show these as a bottom sheet with checkmark-style selection. This makes the count history meaningful — you can query "how much was lost to damage this month".

**Category picker:** The current "Uncategorised ◊" inline text should be a proper form row with the category name on the right and a chevron. When tapped, open a full-screen picker (not a wheel) with all 12 categories listed with checkmarks. Add an "Add Custom Category" row at the bottom (stores in UserDefaults for now, Firestore in Phase 4).

**Expiry Date:** When "Has Expiry Date" toggle is turned ON, animate the date picker into view. Add a hint below it: "You'll get a notification 3 days before this item expires." This surfaces the notification feature that users otherwise wouldn't know exists.

**Quantity fields — numeric keyboard:** All quantity inputs should use `.keyboardType(.decimalPad)`. Verify that the Add/Edit form doesn't use `.default` keyboard for numeric fields, which shows a full QWERTY keyboard on iPhone.

---

## 3.6 — Search & Discoverability Improvements

**Storages list search:** Currently only searches storage name. Add search by location and by item names within the storage. Result format: if the match is on an item inside, show the storage card with a subtitle "Contains: [matched item name]".

**Items tab filter state persistence:** When a user filters by category and then navigates away and back, the filter should reset to "All". Currently unknown — verify and confirm this is the behaviour. If the filter persists between sessions, that can surprise users.

**Spotlight integration:**
Register items and storages with Core Spotlight (`CSSearchableIndex`) when they are created or updated:
```swift
let item = CSSearchableItem(
    uniqueIdentifier: "item-\(inventoryItem.id)",
    domainIdentifier: "com.vishuddhi.smartinventory.item",
    attributeSet: attributeSet
)
CSSearchableIndex.default().indexSearchableItems([item])
```
`attributeSet` should include: title (item name), contentDescription (storage name + SKU), keywords (category, barcode).

Users can then find their items directly from iPhone Spotlight. Tapping the result deep-links to the item detail.

**Filter persistence for Audit tab:** The selected storage chip in the Audit tab should persist across app launches (save to UserDefaults). Most users do their audit storage-by-storage — they shouldn't have to re-select every time.

---

## 3.7 — Data Integrity: Undo + Audit Trail

**Undo for Quick Count (30-second window):**
After a count is saved, show a toast/banner at the top:
```
✓ Count saved for Low Stock Item     [Undo]
```
The Undo button is available for 30 seconds. If tapped, restore the previous quantity and delete the ActivityEvent record. Use a `DispatchWorkItem` that cancels on Undo. This is the gold standard pattern (same as iOS Mail's "Message Sent" undo).

**Count history on Item Detail:**
Add a "Count History" expandable section at the bottom of Item Detail:
```
Count History
Apr 20, 2026 at 11:49 PM   35 → 35   Physical Count
Apr 5, 2026 at 10:05 PM    0 → 35    Item Created
[ Show all ]
```
Pull from `InventoryCount` records for this item. This is already in the data model — just not surfaced in the UI.

**Zero cost validation:**
When a user saves an item with `unitCost = 0`, show a subtle inline warning (not blocking):
```
⚠ Unit cost is $0.00 — Total Value calculations will be affected.
```
This reminds users to set cost and prevents silent Total Value misreporting.

---

## 3.8 — Monetisation: Better Pro Value Communication

**Free tier limit visibility:** Free users should see their limits before they hit them. In StorageListView header, show:
```
Storages  (3 / 5 free)                    +
```
The "3 / 5 free" fades in when the user has 3+ storages. At 5/5, show an amber warning. This primes the upgrade without being aggressive.

**Pro feature previews:** In the paywall, show an animated preview of what Pro unlocks. At minimum, a static screenshot grid of: unlimited storages, full analytics chart, no ads banner hidden.

**Remove Ads product:** Verify it's visible in Profile for users who want ads gone but don't need Pro. Currently the profile only shows "Upgrade to Pro" — add a secondary "Remove Ads — $3.99" row below it for users who are price-sensitive.

**Trial offer:** Add a "Start 7-Day Free Trial" CTA on the paywall. StoreKit 2 supports introductory offers — configure one in App Store Connect and surface it in `PaywallView`. This is one of the highest-impact conversion levers for subscription apps.

---

## 3.9 — Performance: Pagination + Firestore Efficiency

**Item list pagination:** When `items.count > 100`, the `@Query` will return all items and `LazyVStack` will render them all. Add a fetch limit:
```swift
@Query(sort: \InventoryItem.name, order: .forward) private var items: [InventoryItem]
```
Implement pagination using a `fetchLimit` on the descriptor and a "Load More" button at the bottom of the list, or use `onAppear` on the last visible item to trigger the next page.

**Firestore read cost:** The current `pullFromCloud()` reads every document in `storages` and `items` collections on every app launch. For users with 50+ items this becomes expensive. Introduce delta sync: store `lastSyncedAt` timestamp and only pull documents where `updatedAt > lastSyncedAt`. This reduces Firestore reads by ~90% for returning users.

---

## 3.10 — Complete Maestro Flow Testing

**Goal: All non-paywall flows pass reliably. Zero flaky tests. New flows cover Phase 2 features.**

**New flows to add:**

`28_barcode_scan.yaml` — verify scan button is present and scanner opens (can mock the scan result via launchEnvironment).

`29_quick_count_safety.yaml` — verify Save is disabled when quantity is empty; verify large-change confirmation appears; verify Undo toast appears after save.

`30_activity_feed.yaml` — add an item, record a count, verify activity feed shows the event on Dashboard.

`31_reorder_list.yaml` — set an item below min quantity, tap Low Stock KPI card, verify Reorder List shows the item with correct deficit.

`32_swipe_actions.yaml` — verify swipe-to-delete on storage row; verify swipe-to-edit on item row.

`33_spotlight_search.yaml` — (manual only, Maestro cannot control Spotlight) — document in manual_checklist.rtf.

**Flaky test stabilisation:**
- `00_signin_helper.yaml` fails on `"Total Storages"` not visible timing issue. Add `- waitForAnimationToEnd` and increase `timeout` on the assertion to 10 seconds.
- `01_onboarding.yaml` fails on `onboarding.title.0`. Verify accessibility identifier is set on the title element, or switch to assertVisible by text content.

**Target:** All 30+ non-paywall flows pass in a single `maestro test maestro/run_all.yaml` run on a cleanly-launched simulator.

---

## Phase 3 Acceptance Criteria

- [ ] App looks correct and polished in both light and dark mode
- [ ] No hardcoded white/black colours — all adaptive
- [ ] Smart decimal formatting applied everywhere
- [ ] Post-login onboarding modal appears for new users (empty storages)
- [ ] All 5 empty states have illustration, headline, and CTA button
- [ ] Dashboard header shows last sync time dynamically
- [ ] KPI cards show trend indicators (↑↓) based on 7-day ActivityEvent history
- [ ] Donut chart centre label cleaned up
- [ ] UOM label reads "Unit of Measure (UOM)"
- [ ] Adjustment Reason uses bottom sheet picker with 6 predefined reasons
- [ ] Category picker is a full-screen list picker (not inline wheel)
- [ ] Expiry toggle reveals date picker with notification hint
- [ ] Numeric fields use `.decimalPad` keyboard
- [ ] Storages search searches by item names inside
- [ ] Items spotlight-indexed on create/update
- [ ] Audit tab filter chip persists across launches
- [ ] 30-second Undo toast after Quick Count save
- [ ] Count history shown in Item Detail (bottom section)
- [ ] Zero-cost warning shown inline on Add/Edit Item form
- [ ] Free storage limit shown in Storages header (X / 5 free)
- [ ] Remove Ads product visible in Profile
- [ ] 7-day trial CTA on paywall
- [ ] Firestore delta sync implemented (only pull changed records)
- [ ] Item list paginates at 100+ items
- [ ] All 30+ Maestro flows pass in a clean run
- [ ] Flaky signin helper and onboarding flows stabilised
- [ ] New flows 28–32 added and passing
- [ ] Build: 0 errors, 0 warnings

---

---

# PHASE 4 — Power User Layer (previously Phase 2)

- Stock movement log (full transaction history with in/out/transfer types)
- Supplier management (supplier records linked to items)
- Purchase orders (generate from Reorder List, track fulfilment)
- CSV import/export (bulk item import, export to Excel)
- Sub-locations within a storage (Shelf A, Bin 3, Row 2)
- Full activity audit log with filtering by date, user, type
- Custom categories (user-defined, synced to Firestore)

---

# PHASE 5 — Scale & Monetise (previously Phase 3)

- Team roles and permissions (Manager vs Staff vs Read-only)
- Multi-user real-time collaboration (Firestore live listeners)
- Apple Watch companion app (quick count, stock check)
- iOS widget (dashboard KPIs on home screen)
- Siri shortcut / App Intents ("Hey Siri, how many [item] do I have?")
- Advanced analytics (trend charts, turnover rates, dead stock)
- API access for Pro users
- Barcode label printing (AirPrint)
- Pro tier expansion and pricing review

---

*End of Roadmap*
