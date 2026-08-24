# Cursor Spec — iOS-A4b: AddItem/EditItem progressive-disclosure polish

**Base branch:** `iOS-A4b` (already exists, tip = 631f2b3 = same as `iOS-A4`).
**Branches off:** `iOS-A4`.
**Estimate:** 3 story points. One Cursor session.
**Owner:** stoqly-ios-engineer.

---

## Worktree setup (paste block 1)

```bash
cd ~/Documents/My\ Apps/SmartInventory/smart-inventory
git worktree prune
# Old worktree at ../stoqly-iOS-A4b was pruned. Recreate cleanly:
git fetch origin
git worktree add ../stoqly-iOS-A4b iOS-A4b
cd ../stoqly-iOS-A4b
git reset --hard origin/iOS-A4b
git log --oneline -3
# Expect: 631f2b3 iOS-A4: add-item progressive disclosure
```

---

## Load skills in Cursor before writing code

`stoqly-project`, `stoqly-ios-engineer`, `stoqly-product-owner` (read only for context on why this ships), `stoqly-data-analyst` (only to confirm the new analytics event spec).

**CRITICAL RULES to keep in mind (from stoqly-ios-engineer):**
- Every save: `modelContext.safeSave(context: "…")` — never `try? modelContext.save()`.
- `ActivityEvent` insert BEFORE `modelContext.delete(item)` (not relevant here, but keep the muscle).
- Barcode scanner uses `.fullScreenCover`, never `.sheet` (already correct on A4 — do not touch the barcode container).
- Quantities: `Double.smartFormatted`; currency: `String(format: "%.2f", …)`.
- No inner `NavigationStack` inside a sheet (`StorageDetailView` wraps `AddItemView` / `EditItemView` in a `NavigationStack` at the sheet call site — do not add another inside these views).
- SwiftUI `Button` with non-text label inside a `Form`/`List` requires `.buttonStyle(PlainButtonStyle())`.
- Additive-only SwiftData migrations. This story adds no model fields, so no migration.
- Do NOT hardcode `SubscriptionManager.isPro = true` anywhere.

---

## Context — what iOS-A4 already shipped

- `AddItemView` (in `AITest/Views/StorageDetailView.swift`) and `EditItemView` (in `AITest/Views/EditItemView.swift`) now render a "Primary" section (Name + Quantity + Storage on Add, Name + Quantity on Edit) with a "More details" toggle revealing everything else.
- `ItemFormViewModel.canSaveNew` = `!name.isEmpty && hasValidQuantity`. `hasValidQuantity` parses `currentQuantity` as `Double >= 0`.
- `ItemFormViewModel.hasOptionalDetails` is a computed heuristic used by `EditItemView.onAppear` to auto-expand "More details" when the item already has any non-default optional field.
- `ItemPhotoSection` gained `showsSectionContainer: Bool = true` (default preserves prior callers).
- New `sellingPrice` `@State` in `AddItemView`, saved on `item.sellingPrice`.
- Maestro flow 81 (`81_add_item_progressive_disclosure.yaml`) covers the Add path (Name + Quantity → Save).

**Do not redo any of the above.** This story is *polish + small bugs*.

---

## Scope (in-order fix list)

### 1. FIX bug: `sellingPrice` shares focus with `unitCost`

**File:** `AITest/Views/StorageDetailView.swift`

- The `Field` enum currently lacks a `.sellingPrice` case; the `Selling Price` TextField at ~line 692 uses `.focused($focusedField, equals: .unitCost)`. This means unit-cost focus state and selling-price focus state are the same — a subtle bug where dismissing the keyboard or moving focus behaves unexpectedly.
- **Fix:** Add `case sellingPrice` to the `Field` enum. Change the Selling Price `TextField` to `.focused($focusedField, equals: .sellingPrice)`.
- **Acceptance:** Tapping Unit Cost focuses only Unit Cost. Tapping Selling Price focuses only Selling Price. Both fields are independently focusable and dismissible.

### 2. ADD analytics: "More details" toggled event

**Files:** `AITest/Services/AnalyticsManager.swift`, `AITest/Views/StorageDetailView.swift`, `AITest/Views/EditItemView.swift`

- Add a new case to `StoqlyEvent`:
  ```swift
  case addItemMoreDetailsToggled(context: String, expanded: Bool)
  // context: "add_item" | "edit_item"
  ```
- Fire the event inside the "More details" Button action in both `AddItemView` and `EditItemView`, AFTER the `withAnimation { isShowingMoreDetails.toggle() }` call, using the NEW value of `isShowingMoreDetails`.
- Property naming follows the existing convention used by `smartCountModeSelected(mode:)` — snake_case string values.
- **Do NOT** fire the event when `EditItemView.onAppear` auto-expands (that's a system action, not a user tap).
- Update the event's mapping to Amplitude (property dict) alongside the other events in `AnalyticsManager.track`. Follow the pattern used by `paywallShown(source:trigger:)`.
- **Acceptance:** Manual QA: expanding then collapsing "More details" on Add and Edit produces exactly two `add_item_more_details_toggled` events with `context=add_item|edit_item, expanded=true|false`. No event fires on Edit auto-expand.

### 3. POLISH: "Use Template" surface for eligible Pro users

**File:** `AITest/Views/StorageDetailView.swift`

- Currently the `Use Template` button lives INSIDE the collapsed "More details" section (line ~610 on A4). A Pro user with saved templates now has to tap "More details" first to see it — a regression on discoverability.
- **Fix:** When `subscriptionManager.isPro && !templates.isEmpty && teamManager.canEdit`, show a compact chip beside the "More details" toggle button (or as its own row directly above it) labeled `Use Template` with `doc.on.doc.fill` icon. Tapping it opens `showingTemplatePicker` as before.
- Keep the identical duplicated button INSIDE "More details" — no, actually **remove** the in-details copy to avoid duplication.
- Use `.buttonStyle(PlainButtonStyle())` since the chip lives in a Form Section.
- **Acceptance:** Pro user with ≥1 template opens Add Item → sees `Use Template` chip without expanding "More details". Free user or Pro user with 0 templates: chip is absent (unchanged from A4). Edit Item: no change (template use is Add-only).

### 4. POLISH: Primary section header

**Files:** `AITest/Views/StorageDetailView.swift`, `AITest/Views/EditItemView.swift`

- The literal string `"Primary"` as a Section header reads as engineering jargon.
- **Fix:** Drop the header entirely on both views. Use `Section { … }` (no header) for the Name/Quantity/Storage block. This gives the form a cleaner first card and lets "More details" carry the entire visual hierarchy.
- **Acceptance:** Add Item and Edit Item both open showing Name/Quantity/Storage in a headerless top Section. No visual regression.

### 5. POLISH: Save button disabled affordance

**File:** `AITest/Views/StorageDetailView.swift` (AddItemView toolbar), `AITest/Views/EditItemView.swift` (toolbar)

- Verify both toolbar Save buttons apply `.disabled(!formVM.canSaveNew)` / `.disabled(!formVM.canSaveEdit)` respectively.
- Add `.accessibilityHint(Text("Enter an item name and quantity to enable."))` on AddItemView's Save when `canSaveNew == false`. Same pattern for Edit ("Enter a name and quantity.").
- **Acceptance:** VoiceOver on the Save button while fields are empty announces the hint. Tapping while disabled does nothing (already handled by `.disabled`).

### 6. TEST: Maestro flow 82 — Edit auto-expand

**New file:** `maestro/flows/82_edit_item_auto_expand.yaml`

- Mirror `81_add_item_progressive_disclosure.yaml` structure.
- Flow: sign in → open the test warehouse → tap an item known to have a description (or first add one with description via flow 81 pre-step) → open Edit → assert "More details" is expanded on appear (assert Description field is visible without a tap).
- Add the flow to `maestro/run_all.yaml` in the correct numeric slot.
- **DO NOT run `maestro test maestro/run_all.yaml`.** Only run the new flow standalone if strictly required for smoke:
  ```bash
  maestro test maestro/flows/82_edit_item_auto_expand.yaml
  ```
  Prefer skipping this run and letting CEO do manual QA — Maestro `run_all` is DEFERRED per credit cost.

---

## Files touched (expected)

- `AITest/Views/StorageDetailView.swift` — Field enum, sellingPrice focus, Use Template chip surfacing, headerless Primary, Save button hint, moreDetailsToggled analytics.
- `AITest/Views/EditItemView.swift` — moreDetailsToggled analytics, headerless Primary, Save button hint.
- `AITest/Services/AnalyticsManager.swift` — new StoqlyEvent case + property mapping.
- `maestro/flows/82_edit_item_auto_expand.yaml` — new.
- `maestro/run_all.yaml` — insert 82.
- `automation_results.rtf` — append A4b entry.

---

## Definition of Done

1. Xcode build: `xcodebuild -project AITest.xcodeproj -scheme SmartInventory -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` → exit 0, BUILD SUCCEEDED, no new warnings.
2. Field-enum fix verified: `git grep -n "focused(\$focusedField, equals: .sellingPrice)"` returns exactly one match; `git grep -n "focused(\$focusedField, equals: .unitCost)"` returns exactly one match on the Unit Cost field only.
3. Analytics event added and NOT fired on Edit auto-expand.
4. `Use Template` chip visible for Pro+templates+canEdit only; single instance (no duplicate under More details).
5. Section headers on AddItemView and EditItemView top block: no visible header string.
6. `automation_results.rtf` appended with `iOS-A4b` block (same format as prior stories — see A1 entry for the template).
7. Commit + push to `origin/iOS-A4b`:
   ```bash
   git add -A
   git commit -m "iOS-A4b: AddItem/EditItem progressive-disclosure polish (focus fix, moreDetailsToggled event, Use Template chip, headerless Primary, Save hint, flow 82)"
   git push origin iOS-A4b
   ```
8. Open PR against `master_scope_v1` with title `iOS-A4b: AddItem/EditItem progressive-disclosure polish` and body listing the 6 scope items.

---

## Out of scope (do NOT do)

- Do not touch the barcode scanner container (still `.fullScreenCover`).
- Do not touch `SubscriptionManager.isPro`.
- Do not add a `sellingPrice` field to any model — it already exists on `InventoryItem`.
- Do not run `maestro test maestro/run_all.yaml` — DEFERRED per CEO.
- Do not change `hasOptionalDetails` heuristic — A4 tuned it.
- Do not touch `showsSectionContainer` API on `ItemPhotoSection`.
- Do not add a monthly cap to SmartSales (intentional per CEO).

---

## Beyond the ask (for the reviewer)

- **Risk:** Changing the Field enum recompiles focus state across the file. Verify all `.focused($focusedField, equals: …)` sites still map to a valid case.
- **Risk:** The `Use Template` chip surfacing changes IA slightly. If CEO wants A/B before shipping, gate behind a Firebase Remote Config flag — otherwise ship direct.
- **Cheaper alternative:** If time is tight, ship items 1–3 only (bug + analytics + Template chip). Items 4–6 are polish and can defer to A4c.
- **Data governance:** Coordinate the new event `addItemMoreDetailsToggled` with stoqly-data-analyst (Amplitude project 832993) before shipping — it needs a tracking-plan entry.
