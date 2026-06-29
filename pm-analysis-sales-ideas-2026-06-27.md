# PM Analysis — Three Sales Ideas
**Stoqly · CEO Proposal Review**
**Date:** 2026-06-27
**Author:** Product Manager (AI Agent)
**Context:** Phase 7A just shipped. SaleEvent model, QuickSaleSheet, ReportsView, and MovementsListView are live.

---

## Executive Summary

| Idea | Recommendation | Phase | Complexity |
|------|---------------|-------|------------|
| Idea 1 — Bulk/AI Sales Import | Defer to 7B with one scoping decision needed | 7B | Large (3+ days Cursor) |
| Idea 2 — Swap Audit tab with Sales tab | Reject as proposed; recommend hybrid (tab rename + keep workflow) OR defer decision post-launch | Post-launch | Medium (1–3 days) |
| Idea 3 — Empty state CTA + persistent Record Sale button | Ship now in 7B | 7B | Small (<1 day Cursor) |

---

## Idea 1 — Bulk/AI Sales Import ("Smart Sales Entry")

### What the CEO is proposing
A voice or photo → AI → bulk `SaleEvent` records flow, analogous to how `VoiceInventoryView` lets users count inventory hands-free. The user would speak (or photograph) a batch of sales, AI parses them, user reviews, and a batch of `SaleEvent` records is committed.

### Is this already in the roadmap?
Partially. Phase 7B explicitly deferred "voice sales entry." This idea expands that to also include photo/paper input (like `PaperInventoryView` does for counting), but the voice path directly overlaps with the deferred item. **This is not new scope — it is an expansion of a planned 7B item.**

### Architecture assessment

The infrastructure for this feature already exists and is well-factored:

- **`AIInventoryService`** already has three parse modes (voice transcript, product photo, inventory sheet). A fourth method — `parseSalesTranscript` / `parseSalesSheet` — would follow the identical pattern.
- **`VoiceRecordingController`** + `SpeechKit` nonisolated helpers are reusable as-is. No changes needed.
- **`SmartCountView`** is the mode-picker shell that presents Voice / Photo / Sheet cards. A `SmartSalesView` would mirror this exactly.
- **`SaleEvent`** model is already complete and supports all the fields needed (item, qty, pricePerUnit, costPerUnit, notes, date).
- **`AIUsageManager`** already has a rate-limiting pattern (free: 3/month per mode). A new `.sales` usage type can be added.
- **`QuickSaleSheet`** handles the save path — the bulk flow would need an `EditableSaleItem` equivalent and a `BulkSaleSaveView` (equivalent to the VoiceInventoryView review step).

The key difference from inventory counting: sales require a **selling price**, which is optional in QuickSaleSheet (falls back to `item.sellingPrice`). AI parsing of a spoken sales statement ("I sold 3 coffees at $4.50 and 2 muffins at $3") is a well-defined NLP task that Claude handles cleanly.

### Critical differences from VoiceInventoryView

| Aspect | Voice Inventory Count | Voice/Photo Sales Entry |
|--------|----------------------|-------------------------|
| Output per item | qty (and optionally UOM) | qty + selling price |
| Item resolution | matches by name in selected storage | must also resolve item identity |
| Quantity direction | SET to (or ADJUST by) | SUBTRACT from stock |
| Fallback if item unknown | creates new item | cannot create — must link to existing or skip |
| Price source | N/A | user-spoken price OR item.sellingPrice fallback |

This "item must already exist" constraint is the most important architectural point. The review step for sales bulk import needs a picker to link parsed names to existing items — the `ItemMatchReviewControls` + `LinkExistingItemPickerSheet` already exist for this exact purpose and can be reused.

### Risks and open questions

**RISK 1 — Scope creep from "similar to inventory counting" framing.**
Inventory counting is forgiving: unrecognised items get created. Sales import is not: unrecognised item names must be skipped or manually linked. This makes the review step meaningfully more complex.

**RISK 2 — Price ambiguity in voice input.**
"I sold 5 coffees" — at what price? If `item.sellingPrice` is set, we can default. If not, the review step must force the user to enter a price, which changes the UX flow. We need a decision on this.

**RISK 3 — Monetisation gate.**
Current `AIUsageManager` has a `.voice` type. Do we gate sales AI separately from inventory AI, or pool them? This affects the free tier value proposition.

**RISK 4 — 7B scope already large.**
Phase 7B was already deferred with at least voice sales entry in scope. M6 SMB review gaps (6 items) are still pending Cursor. Stacking a full SmartSalesView + EditableSaleItem + BulkSaleSaveView on top risks overfilling the phase.

### Critical Decision Protocol (CDP) — CEO must decide

> **CDP 1A:** Should "Smart Sales Entry" be voice-only in 7B, or include photo + paper sheet modes too?
> - Voice-only: smaller scope, ships in 7B, aligns with original 7B plan.
> - All three modes: matches SmartCountView parity, but Large complexity, risks delaying 7B.

> **CDP 1B:** When AI parses a spoken/photographed item name that doesn't match any existing item in the user's inventory, what happens?
> - Option A: Skip it, show a warning in the review step.
> - Option B: Show an "unresolved" row that the user must manually link before saving.
> - Option C: Allow saving with just the name as a string (no item link) — revenue tracked but no stock deduction.

> **CDP 1C:** AI usage gating — does sales AI consume from the same monthly free pool as inventory AI, or is it a separate gate?

### PM Recommendation
**Defer to 7B — voice-only first.** Scope it as: `SmartSalesView` (voice mode only) → `EditableSaleItem` review list (reusing `ItemMatchReviewControls`) → batch save to `SaleEvent`. Answers to CDP 1A–1C are needed before Cursor spec can be written. Estimated complexity: **Large (3–4 days Cursor)** for voice-only; add another 1–2 days for photo/sheet modes.

---

## Idea 2 — Swap "Audit" Tab with "Sales" Tab

### What the CEO is proposing
Replace the current Audit tab (Tab 3, `CountView`) with a Sales tab pointing to a `SalesView` (probably the content currently in `ReportsView`). The CEO's stated rationale: "Items and Audit serve the same purpose, why can't we swap anyone (perhaps audit) with Sales instead."

### Are Items and Audit actually the same? A direct comparison.

They are **not** the same. This is the most important factual point to resolve before the decision.

**Items tab (`ItemListView`)** — an operational catalogue:
- Shows ALL items across ALL storages in a flat searchable list
- Primary actions: **add item, edit item, delete item, export**
- Has barcode scanner ("Scan to Find") for item lookup
- Has Smart Count launcher (sparkles icon)
- Supports category/stock-status filters
- Used to **manage the inventory catalogue** — what exists, what it's called, what it costs

**Audit tab (`CountView`)** — a count workflow engine:
- Shows items **prioritised by when they need to be counted** (Due / Uncounted / Low Stock / All)
- Primary action: **tap to count** (opens QuickCountView or CountItemView)
- Has a session tracker ("3 of 12 counted" progress indicator, checkmarks fade counted items)
- Has per-storage filter chips for focused counting sessions
- "Smart Count" (AI) is in the toolbar here too, but it leads to counting, not browsing
- Used to **run a physical count session** — work through a prioritised list to completion

The CEO's intuition is understandable: both tabs show items. But the cognitive model is different:
- Items = "what do I have in my catalogue?" (noun: the inventory)
- Audit = "what do I need to count today?" (verb: an ongoing task queue)

Removing Audit from the tab bar would bury a feature that SMBs use on a regular, recurring schedule (weekly/monthly count cycles). Every inventory management product — from Square to Lightspeed to Shopify POS — treats inventory counting as a first-class workflow. Burying it in a sub-menu risks a 7/10 → 5/10 regression on the "Feature Completeness" and "UX & Usability" expert rating dimensions.

### The actual problem the CEO is solving

Sales is currently buried: `Dashboard → "Sales Performance" card → tap → ReportsView (sheet)`. There is no direct entry point to record a sale from anywhere except `StorageDetailView` swipe or `ItemDetailView`. The CEO is right that Sales needs more prominence. The question is whether Audit must die for Sales to live.

### Option analysis

**Option A — Replace Audit with Sales (as proposed)**
- Risk: count workflow loses top-level access; power users will complain; App Store reviewers who value inventory features may downgrade rating.
- Impact on Maestro: 27 flows reference Audit/Count tab (flows touching `auditCountCard_*` accessibilityIdentifiers). All would need updating.
- Not recommended.

**Option B — Replace Items with Sales**
- The Items tab is also reachable from Storages → Storage → items list. Is it a top-level destination?
- Risk: Items provides the "global view across all storages" that isn't available from Storages tab. Removing it breaks the mental model of "see everything I own."
- Not recommended.

**Option C — Rename Audit → Sales, merge the Count workflow into it**
- Rename the tab to "Sales" with a new icon (e.g., `chart.bar.fill` or `cart.fill`).
- Top of the tab shows a Sales summary (today's revenue, quick "Record Sale" button).
- Below (or in a segmented control): the Count workflow (currently in CountView).
- Pro: Sales gets a tab without evicting Audit.
- Con: Two unrelated workflows in one tab is awkward; Maestro flows would need tab label updates.
- Medium complexity (1–2 days Cursor).

**Option D — Dedicated Sales tab replaces Profile tab**
- Profile (Settings, Export, Team, Subscription) is accessed infrequently — it is a settings surface, not a daily workflow.
- Move Profile into Dashboard overflow menu or Settings via a toolbar button.
- Add a Sales tab in position 4.
- This is a legitimate architecture decision but has its own tradeoffs (Profile is also where Subscription management lives — should always be reachable for the business model).

**Option E — Add a 6th tab (5 → 6 tabs)**
- iOS HIG allows up to 5 tabs before TabView adds a "More" overflow. Adding a 6th tab on iOS pushes the last items into a "More" list — a known UX anti-pattern. Not recommended.

### Critical Decision Protocol (CDP) — CEO must decide

> **CDP 2A:** Is the primary goal to make "Sales" a top-level destination, or to demote "Audit"? These are separate decisions.

> **CDP 2B:** If Sales gets a tab, which existing tab is removed or merged?
> - Option C (merge Sales summary + Count into one "Sales & Audit" tab)
> - Option D (move Profile to toolbar/settings gear, give tab slot to Sales)
> - A different arrangement the CEO prefers?

> **CDP 2C:** What content should a dedicated Sales tab show? Is it the current `ReportsView` content, a new lighter-weight "Today's Sales" view, or both with a segmented control?

### PM Recommendation
**Do not remove the Audit tab in 7B.** The count workflow is a core SMB use case and a key differentiator. Recommend **deferring this navigation restructure to a post-launch decision** informed by real user data (which tabs do users actually visit most?). If the CEO wants to act before launch, **Option D** (Profile moves to a gear icon in Dashboard header, Sales takes tab slot 4) is the cleanest architectural path. Complexity: **Medium (1–2 days Cursor)** for Option D.

---

## Idea 3 — Empty State CTA + Persistent "Record Sale" in Reports View

### What the CEO is proposing
- **Empty state:** When `ReportsView` has no sales for the selected period, show a tappable button "Record Your First Sale" instead of just the `ContentUnavailableView` label.
- **Non-empty state:** Add a persistent "Record Sale" button (FAB or toolbar button) so users can record a sale without leaving ReportsView and navigating back to a storage.

### Is this already in the roadmap?
No. This is net-new UX polish, but it is small and well-scoped.

### Architecture assessment

**Where to make the change:** `ReportsView.swift`, specifically the `summaryCard` computed property (lines 175–199) for the empty state, and the `.toolbar` block (lines 112–117) for the persistent button.

**Empty state CTA:** The current empty state uses `ContentUnavailableView` with no action. Adding a `.actions { }` block with a "Record Sale" button is a one-liner in iOS 17+. The button needs to present `QuickSaleSheet`, but `QuickSaleSheet` requires an `InventoryItem`. If no item is pre-selected, the CTA should instead open a lightweight "choose an item, then record sale" flow. Options:
- A: CTA opens a `ItemPickerSheet` → user selects item → `QuickSaleSheet` opens.
- B: CTA opens `StorageDetailView` (navigates user to Storages tab to pick an item).
- C: CTA presents a simplified sale sheet with an item picker embedded.

**Persistent FAB / toolbar button:** `ReportsView` currently has a `Done` toolbar button (top-right). A "+" or `cart.badge.plus` icon can go top-left as a toolbar item. This again needs an item-picker if no context item is passed in.

**Key constraint:** `ReportsView` is always presented as a sheet (`.sheet(isPresented: $showingReports)` from `DashboardView`). Nested sheets work fine on iOS 16+ as long as we don't present another `.sheet` inside the same `NavigationStack`. Since `QuickSaleSheet` already uses `.sheet`, this is safe.

**Item picker requirement:** The picker should show all items, grouped by storage, searchable. `ItemListView` already exists as a full list — a trimmed-down `SaleItemPickerSheet` (searchable list, tap to select) would be ~60 lines and is the right component here.

### Risks and open questions

**RISK 3A — "Record Sale" from Reports requires an item context.** Unlike QuickSaleSheet called from StorageDetailView (which already knows the item), the Reports view has no item context. The flow needs a picker. We must decide: inline picker inside a new sheet, or navigate the user to Items/Storages?

**RISK 3B — Empty state CTA messaging.** "No Sales This Period" + "Record your first sale" implies the user hasn't used the feature. But the empty state also shows during a period filter where sales exist but outside the window (e.g., filtering "Today" when all sales were last week). The CTA copy should not say "first" — it should say "Record a Sale" regardless of history.

**RISK 3C — Presentation nesting depth.** ReportsView is already inside a sheet from Dashboard. If CTA opens an ItemPickerSheet (another sheet), and then QuickSaleSheet (another sheet), that's 3 levels of sheet stacking. iOS handles this, but it's worth noting. Use `.fullScreenCover` for QuickSaleSheet if nesting feels heavy.

### Critical Decision Protocol (CDP) — CEO must decide

> **CDP 3A:** For the "Record Sale" button in ReportsView, how should item selection work?
> - Option A: Show a searchable item picker sheet (new `SaleItemPickerSheet`), then QuickSaleSheet.
> - Option B: Navigate to the Items tab (close Reports, switch selectedTab to 2), let user swipe to record sale from there.
> - Option C: The "Record Sale" button in Reports only appears if there's exactly one item in the inventory (edge case — probably not worth designing around).
> - **PM leans toward Option A** — fewest steps, stays in context.

### PM Recommendation
**Ship in 7B.** This is the highest-confidence, lowest-risk of the three ideas. Complexity: **Small (<1 day Cursor)**. Even without a resolved CDP 3A, the empty state improvement (removing the passive `ContentUnavailableView` message and adding an action button) can ship independently of the item-picker decision. The toolbar button in the non-empty state can ship once CDP 3A is resolved.

Cursor spec items:
1. `ReportsView.summaryCard` — add `.actions { Button("Record a Sale") { showingItemPicker = true } }` to the `ContentUnavailableView` block.
2. `ReportsView` toolbar — add a `cart.badge.plus` toolbar item (leading position) that sets `showingItemPicker = true`.
3. New `SaleItemPickerSheet` — searchable `List` of all items grouped by storage; `onSelect: (InventoryItem) -> Void` callback; presented as a `.sheet`.
4. Wire: `SaleItemPickerSheet` → dismisses → `showingQuickSale` with the selected item.

---

## Proactive Protocol — Cross-Idea Risks and Downstream Impacts

### P1 — M6 is still pending Cursor
M6 SMB review gaps (multi-storage reorder email, per-item % threshold, offline write queue, daily summary notification, cost layer foundation) are written in `todolist.rtf` but have NOT run yet. Adding three new ideas into the planning queue risks M6 never getting run. **Recommendation: run M6 first, then spec 7B items.**

### P2 — Phase 5.3 conflict
The roadmap lists "Manual sales entry (SaleEvent model, velocity calculation, sales analytics)" as Phase 5.3 (post-launch). Phase 7A has already shipped a full `SaleEvent` model and `ReportsView`, meaning Phase 5.3 is substantially done ahead of schedule. The phase-status.md roadmap is now stale on this point and should be updated to reflect that 5.3 is complete in all but velocity calculations.

### P3 — Tab navigation Maestro impact
Any change to the bottom tab bar will break Maestro flows that tap specific tab indices. Current suite has 80 flows. A tab restructure requires a sweep of all `tapOn: "Audit"`, `tapOn: "Profile"`, and tab-index-based navigation. This is a meaningful testing tax: estimate 0.5–1 day of Maestro updates per tab changed.

### P4 — `SubscriptionManager.isPro` still hardcoded `true`
All three ideas involve features that may be Pro-gated (AI sales import is clearly Pro). If any of these ship before `isPro` is reverted to `false`, the gate won't be testable. This is the single highest-priority pre-ship task and is not blocked by any of these feature decisions.

### P5 — No `SaleEvent` Firestore push path audit
`QuickSaleSheet` calls `FirestoreManager.shared.pushSaleEvent(sale)`. If AI bulk sales import is added, each saved sale in the batch must also push to Firestore. The `VoiceInventoryView` does a `syncItem` per item (not a dedicated push). We need to confirm `pushSaleEvent` exists and handles the batch case correctly before speccing bulk save logic.

### P6 — Items tab Smart Count duplication
`ItemListView` has its own "sparkles" Smart Count button in the toolbar. `CountView` also has a sparkles button. If a "SmartSalesView" is also accessed from a Sales tab (or Reports), there will be three separate "sparkles" entry points that do different things (inventory count vs. sales). Users will get confused. Consider standardising the Smart AI icon or labelling them differently ("Count", "Sales", "Import").

---

## Summary of CEO Decisions Needed Before Speccing

| # | Idea | Decision | Options |
|---|------|----------|---------|
| CDP 1A | Idea 1 | Voice-only or all three modes (voice + photo + sheet) in 7B? | Voice-only (recommended) / All modes |
| CDP 1B | Idea 1 | Unresolved item names in AI sales parse: skip, force-link, or save as name-only? | A: Skip / B: Force-link / C: Name-only |
| CDP 1C | Idea 1 | AI usage gating: shared pool with inventory AI or separate sales gate? | Shared / Separate |
| CDP 2A | Idea 2 | Primary goal: elevate Sales OR demote Audit? (separate decisions) | Clarify intent |
| CDP 2B | Idea 2 | If Sales gets a tab slot, which tab moves/merges? | Option C (merge) / Option D (Profile to toolbar) / Other |
| CDP 2C | Idea 2 | What does a Sales tab show? ReportsView content / new lighter view / segmented both? | Clarify |
| CDP 3A | Idea 3 | "Record Sale" from Reports — how does item selection work? | A: Picker sheet (recommended) / B: Navigate to Items tab |

---

*Prepared by PM Agent · stoqly-project skill · 2026-06-27*
*Read automation_results.rtf before acting on any M6 items — it is the authoritative log.*
