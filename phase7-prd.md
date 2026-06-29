# FEATURE SPEC — Phase 7: Sales, Profitability & Reports
**Role:** Product Manager  
**Date:** 2026-06-27  
**Status:** READY FOR DESIGNER + ENGINEERING

---

## 0. Executive Context

Beta users are not asking for more inventory features — they're asking: *"Am I making money?"* Profitability insight is the single highest-leverage gap between Stoqly and App Store approval. Without it, the app helps users know *what* they have but not *whether their business is healthy*. That is an incomplete product for an SMB.

**Gate:** Phase 7 must ship before App Store submission. No exceptions.

**SMB Review Target:** ≥ 7/10 in Profitability Insights dimension.

**Existing assets discovered (do NOT rebuild):**
- `VoiceInventoryView.swift` — full SFSpeechRecognizer pipeline already built with Swift 6 actor isolation fixes
- `CurrencyManager` + `Currency.swift` — currency picker + `formatPrice()` already exists; just needs locale auto-detect + broader wiring
- Anthropic API key infrastructure (Secrets.plist + `AIAPIKeyRow` in Settings) — ready to use for AI assistant
- `ExportManager.swift` — PDF + CSV export already built; extend for reports

---

## 1. Problem / Job-to-be-Done

**Who hurts:** Every café owner, restaurant manager, and shop keeper using Stoqly. They track stock but have no answer to:
- "Did I make a profit this month?"
- "Which items are draining my margins?"
- "How much stock did I buy vs. sell this week?"
- "Why is my cash low even though sales are okay?"

**Pain severity:** 9/10. Without this, Stoqly is a glorified stockroom counter — useful but not essential. WITH it, Stoqly becomes the financial pulse of the business.

---

## 2. Why Now / Link to Roadmap Gate

Phase 7 is declared the new pre-ship gate. The previous Phase 5 (Sales) and Phase 6 (AI) have been pulled forward and merged into Phase 7 because beta user feedback is unambiguous: profitability is table-stakes, not a nice-to-have.

Competing apps (Sortly, inFlow, Cin7) ALL have sales tracking. Without it, Stoqly will be rated 3–4/10 on profitability by any SMB reviewer, which is an App Store rejection risk for discoverability.

---

## 3. Target Users

| Persona | Context | Core need |
|---------|---------|-----------|
| Café owner (primary) | Tracks ~50 items, buys ingredients weekly | "How much did I spend vs. earn this month?" |
| Restaurant manager | High turnover, multiple storages | "Which dishes are killing my margins?" |
| Shop keeper | Retail, sells individual items | "My revenue is ₹80k, what's my profit?" |
| Warehouse manager | B2B, large volumes | "Show me inventory movement report for audit" |

---

## 4. Phase Scoping: 7A (Pre-Ship MVP) vs. 7B (Post-Launch)

### Phase 7A — Must Ship Before App Store

| Feature | Why it's in |
|---------|-------------|
| Selling price per item | Without this, profit is impossible to calculate |
| Quick Sale entry (manual) | Core sales recording — 1 item at a time, fast |
| Inventory Movement log (IN/OUT with types) | Audit trail + report feed |
| Profitability per item (margin %) | Single most-requested insight |
| Dashboard: Revenue + Gross Profit KPI cards | Answers "am I making money?" at a glance |
| Reports screen (Sales + Profit, by period) | Period-based insight: today / week / month / custom |
| Currency: locale auto-detect on first install | Removes confusion for non-USD users (bug from beta) |
| Currency: fix consistency across all 5 views | Eliminates the ₹ vs $ mismatch bug |

### Phase 7B — First Post-Launch Update (2–3 weeks after ship)

| Feature | Why it's deferred |
|---------|-------------------|
| Voice sales entry | Voice infra exists but needs sales-specific parsing; safe to defer |
| Excel/sheet import for sales history | Engineering complexity; not blocking launch value |
| AI search/query assistant ("What's my best margin item?") | Anthropic API key exists, but UX needs more thought; too complex for 7A |
| Multi-storage sales attribution | Adds complexity; single-storage sale is enough for 7A |
| PDF export of profit report | ExportManager needs extension; defer to 7B |
| Sales tax / VAT tracking | Legal/financial complexity; out of scope entirely for MVP |
| COGS (cost of goods sold) full P&L statement | Advanced accounting; target CPAs not SMBs in MVP |

### OUT OF SCOPE (all phases)

- Currency conversion with exchange rates (just symbol/format, not value conversion)
- Point-of-sale (POS) hardware integration
- Customer management / CRM
- Invoice generation
- Tax filing / accounting export (QuickBooks, etc.)

---

## 5. User Stories with Acceptance Criteria

---

### Story 7A-1: Add Selling Price to Items

**As a** shop owner,  
**I want** to set a selling price for each item (separate from my cost price),  
**so that** Stoqly can calculate my profit margin automatically.

**Acceptance criteria:**
- Given I am on the Add/Edit Item form, when I open it, then I see a "Selling Price" field below the existing "Unit Cost" field.
- Given I enter a unit cost of ₹100 and a selling price of ₹150, when I save the item, then the item detail shows: "Margin: 33%" (or equivalent display).
- Given selling price is 0 (not set), when viewing the item, then margin is shown as "—" (not 0% or a confusing value).
- Given I import items via CSV/Excel bulk import, when the file has a "Selling Price" or "Sale Price" or "MRP" column, then it maps to this field automatically.
- The selling price field is optional (existing items without it continue to work).
- Firestore syncs `sellingPrice` with the same pattern as `unitCost`.

**Out of scope:** Different selling prices for different customers.  
**Role owner:** iOS + Backend

---

### Story 7A-2: Record a Quick Sale

**As a** café owner,  
**I want** to record a sale of an item with quantity and selling price,  
**so that** my stock automatically decreases and the sale is captured for reporting.

**Acceptance criteria:**
- Given I am on StorageDetailView or ItemDetailView, when I tap the "Record Sale" button (new), then a Quick Sale sheet opens showing the item name, current stock, default selling price (from item's `sellingPrice`), and a quantity field.
- Given I enter a quantity to sell and confirm, when the sale is saved, then: (a) the item's `currentQuantity` is reduced by the sold quantity, (b) a `SaleEvent` is created, (c) a `ActivityEvent` of type `"SaleMade"` is logged, (d) an `InventoryMovement` of type `"SaleOut"` is created.
- Given the quantity entered exceeds current stock, when I try to save, then a warning is shown: "Selling X but only Y in stock. Confirm?" — user can override.
- Given I do not change the selling price in the sale sheet, then the default selling price from the item is used.
- Given selling price in the sale differs from item's default selling price, then the `SaleEvent` records the actual price (not the default).
- A sale can be undone from the activity feed within the same app session (nice-to-have, not required for 7A).

**Out of scope:** Multi-item sale (shopping cart), receipt generation.  
**Role owner:** iOS + Backend

---

### Story 7A-3: Log Inventory Movements (IN / OUT)

**As a** restaurant manager,  
**I want** to record why stock went up or down (purchase, waste, transfer, return),  
**so that** I have a clear audit trail and accurate movement reports.

**Acceptance criteria:**
- Given I am on ItemDetailView, when I tap "Add Movement" (new), then a sheet opens with: movement type picker, quantity, price per unit (optional), notes, date (default = now).
- Given I select movement type, then the types available are:
  - **IN types:** Purchase, Transfer In, Return from Customer, Adjustment (Up), Opening Stock
  - **OUT types:** Sale (links to SaleEvent flow), Waste / Spoilage, Transfer Out, Return to Supplier, Adjustment (Down)
- Given I confirm a movement, then the item's `currentQuantity` adjusts accordingly (IN = increase, OUT = decrease), an `InventoryMovement` record is created, and an `ActivityEvent` of type `"MovementLogged"` is created.
- Given I select "Purchase" (IN), then the price per unit field is labeled "Purchase Price" and pre-filled with the item's `unitCost` (editable).
- Given I select "Waste / Spoilage" (OUT), then the price per unit field is labeled "Waste Cost" and pre-filled with `unitCost`.

**Out of scope:** Batch movement import, automatic movement from supplier invoices.  
**Role owner:** iOS + Backend

---

### Story 7A-4: View Profitability per Item

**As a** shop owner,  
**I want** to see the gross profit margin for each item at a glance,  
**so that** I can identify which items I should promote more and which I should stop carrying.

**Acceptance criteria:**
- Given I am on ItemDetailView, when I open it, then I see a "Profitability" section showing: Unit Cost, Selling Price, Gross Profit (per unit), and Gross Margin %.
- Given an item has no selling price set, when I view ItemDetailView, then the profitability section shows a "Set selling price to see margin" prompt with a tap-to-add action.
- Given I am on the new Reports screen → "Top Performers" sub-view, when it loads, then it shows a ranked list of items by Gross Margin % (highest first), with margin %, cost, and selling price visible for each.
- Given I am on Reports → "Margin Alerts" sub-view, when it loads, then it shows items with margin < 10% as "Low margin" in orange, and items with selling price ≤ cost price as "Selling at a loss" in red.
- Margin formula: `(sellingPrice - unitCost) / sellingPrice × 100`

**Out of scope:** Multi-level margin (considering transport, labour), blended margin across batch purchases.  
**Role owner:** iOS + Designer

---

### Story 7A-5: Reports Screen — Sales & Profit by Period

**As a** restaurant manager,  
**I want** to see my sales and profit for a selected period (today, this week, this month, custom),  
**so that** I can track my business performance over time without needing a spreadsheet.

**Acceptance criteria:**
- Given I navigate to the Reports section (see Story 7A-6 for navigation decision), when it loads, then I see a period selector at the top: Today / This Week / This Month / Last 30 Days / Custom.
- Given I select "This Month," when the report loads, then I see:
  - **Revenue:** total selling price × qty for all SaleEvents in the period
  - **COGS:** total cost price × qty for all SaleEvents in the period
  - **Gross Profit:** Revenue − COGS
  - **Gross Margin %:** (Gross Profit / Revenue) × 100
  - **Units Sold:** total quantity across all SaleEvents
  - A bar chart of daily revenue for the period (or weekly bars for "This Month")
- Given I tap on any metric, then I see a breakdown by category (Food & Beverage: ₹X, Packaging: ₹Y, etc.).
- Given there are no sales in the selected period, then an empty state reads: "No sales recorded for this period. Tap '+' to record your first sale." with a CTA button.
- Given I am a Free user, then I can view reports for the last 30 days only; periods beyond 30 days are paywalled with a Pro upsell.
- Given I am a Pro user, then custom date range is available with no restriction.

**Out of scope for 7A:** PDF export of report, sharing report as screenshot, scheduled report emails.  
**Role owner:** iOS + Designer

---

### Story 7A-6: Reports Navigation (DECISION NEEDED — see §9)

**As a** user,  
**I want** to find Sales/Profit reports intuitively without hunting through menus,  
**so that** I check my business performance daily without friction.

**Acceptance criteria (contingent on navigation decision):**
- The Reports entry point is reachable in ≤ 2 taps from any main screen.
- The Reports section is clearly labeled and distinct from the inventory Audit/Count tab.
- Pro gating is visible and non-intrusive on the Reports screen.

**Decision needed:** See §9.  
**Role owner:** Designer + iOS

---

### Story 7A-7: Currency Locale Auto-Detection

**As a** new user in India,  
**I want** the app to automatically show Indian Rupee (₹) when I first install,  
**so that** I don't need to manually change currency before I can use the app meaningfully.

**Acceptance criteria:**
- Given a new install on a device with locale `en_IN` or region code `IN`, when the app launches for the first time, then `CurrencyManager.selectedCurrency` is set to `INR` (Indian Rupee) without user action.
- Given a new install on a device with locale `en_US`, when the app launches for the first time, then `CurrencyManager.selectedCurrency` defaults to `USD`.
- Given the device locale is not in `Currency.currencies`, when the app installs, then it falls back to `USD`.
- Given the user has previously set a currency manually, when the device region changes to a different country, then on next app launch (foreground), a banner or alert appears: "Your device region changed to [Country]. Switch to [Currency]?" with "Switch" and "Keep current" options.
- The locale-change detection must NOT fire on every launch — only when the locale-derived currency differs from the saved currency and the user hasn't explicitly dismissed the prompt for this locale change.

**Out of scope:** Currency value conversion, exchange rate APIs.  
**Role owner:** iOS

---

### Story 7A-8: Currency Symbol Consistency

**As a** user,  
**I want** the selected currency symbol to appear everywhere prices are shown,  
**so that** I don't see ₹ in one place and $ in another.

**Acceptance criteria:**
- Given I have set currency to INR, when I view any of the following, then all prices show ₹ symbol (not $):
  - Dashboard Total Value KPI
  - StorageDetailView Total Value header
  - StorageDetailView item row price
  - ItemDetailView unit cost and total value
  - ValueByCategoryView Total + per-category values
  - ReportsView all monetary values
- All monetary display must go through `currencyManager.formatPrice()` — no hardcoded `$` or `String(format: "%.2f", ...)` without currency symbol.
- `CurrencyManager` must be provided as `.environmentObject()` at the `InventoryAppView` root, and all child views must receive it via `@EnvironmentObject`.

**Out of scope:** Converting stored values (unit costs, totals) — only the display symbol changes.  
**Role owner:** iOS

---

## 6. Success Metrics

### Primary Metrics (Phase 7A — measure 2 weeks post-launch)

| Metric | Target | How to measure |
|--------|--------|---------------|
| Sales recorded per active user per week | ≥ 3 sales/user/week | `SaleEvent.savedAt` count per user per 7-day window |
| Profitability margin set (% of items with sellingPrice > 0) | ≥ 50% of items after 7 days | `InventoryItem.sellingPrice > 0` count / total items |
| Reports tab DAU | ≥ 20% of DAU visit Reports weekly | Screen view event on ReportsView |
| SMB user review score — Profitability dimension | ≥ 7/10 | Run SMB review skill post-build |

### Guardrail Metrics (must NOT regress)

| Metric | Threshold | Risk |
|--------|-----------|------|
| App crash rate | < 0.5% | New SwiftData models could cause schema migration issues |
| Core inventory workflow completion (add item → count) | No regression | New tab/navigation change could break existing flows |
| Onboarding completion rate | No regression | Currency auto-detect prompt could confuse new users |

### Analytics Events to Instrument

```
sale_recorded       { item_id, qty, selling_price, cost_price, profit, storage_id }
movement_logged     { item_id, movement_type, qty, price_per_unit }
report_viewed       { period_type: "today|week|month|custom", date_range }
selling_price_set   { item_id, source: "edit_form|quick_sale" }
currency_changed    { from_code, to_code, method: "auto_detect|manual|locale_prompt" }
profit_insight_tapped { item_id, insight_type: "top_performer|margin_alert" }
```

---

## 7. Dependencies

| Dependency | Blocks | Notes |
|-----------|--------|-------|
| `SaleEvent` SwiftData model | Stories 7A-2, 7A-5 | New model, schema migration required |
| `InventoryMovement` SwiftData model | Story 7A-3 | New model, schema migration required |
| `sellingPrice: Double` on `InventoryItem` | Story 7A-1 | Field addition, Firestore sync update |
| Firestore schema update | Stories 7A-1, 7A-2, 7A-3 | New subcollections or fields under users/{uid}/ |
| Navigation decision (§9) | Story 7A-6 | Designer must decide before engineering starts |
| `CurrencyManager` environment propagation | Story 7A-8 | Root-level `.environmentObject()` must be verified |
| SwiftData migration strategy | All new models | Cannot break existing Phase 1–6 data |

---

## 8. Rollout

- **Platform:** iOS only (no Android in this org)
- **Feature flag:** None required — Phase 7A ships as a new tab/section visible to all users
- **Pro gating:**
  - Sales recording → FREE (drives engagement, hook for upgrade)
  - Inventory movements → FREE
  - Profitability per item → FREE (key value prop)
  - Reports: last 30 days → FREE; beyond 30 days + custom range → PRO
  - Export of profit report (Phase 7B) → PRO
- **Rollout sequence:** Internal TestFlight → invite-only beta (current beta users) → App Store

---

## 9. Open Decisions (MUST be resolved before engineering starts)

### DECISION NEEDED A — Reports Navigation Location

**Why it's critical:** Changes tab structure — hard to undo, affects all existing users.

**Options:**
- **A1. New 6th tab "Reports"** — iOS shows "More…" on iPhone for 6+ tabs. ❌ Poor UX.
- **A2. Replace "Profile" tab with "Insights" tab** — Profile accessible via gear icon on Dashboard. ✅ Clean. 5 tabs preserved.
- **A3. Reports as a sheet launched from Dashboard "View Reports →" button** — No tab change. ✅ Lowest engineering risk, but buried.
- **A4. Rename current "Audit" tab → "Insights" and put Sales/Reports alongside Audit/Count** — Makes Insights a superset. ✅ Cohesive.

**My recommendation: A4** — "Insights" tab replaces "Audit" tab. Inside Insights: top section = Sales & Profit reports; bottom section = Audit (count history, never audited). This is the most intuitive for SMB: one place for all business intelligence.  
**Confidence: medium** (Designer should validate)  
**If I don't hear back:** Engineering holds on tab structure; proceeds only with data model work.

### DECISION NEEDED B — SwiftData Migration Strategy for New Models

**Why it's critical:** Adding `sellingPrice` to `InventoryItem` requires a migration. Bad migration = existing user data lost.

**Options:**
- **B1. `ModelConfiguration` with `VersionedSchema`** — proper SwiftData migration, safe but complex.
- **B2. Optional field with default** — `var sellingPrice: Double = 0` as lightweight migration (SwiftData handles new fields with defaults automatically in most cases).

**My recommendation: B2** — Use `= 0` defaults for all new fields on existing models. New models (`SaleEvent`, `InventoryMovement`) are additive. **Confidence: high.**  
**If I don't hear back:** Engineering uses B2.

---

## 10. Risks & Beyond the Ask (Proactive Protocol)

### Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| SwiftData migration corrupts existing inventory data | Low | Critical | Test migration on device with existing data before beta; use `= 0` defaults |
| Selling price as a concept confuses users who don't sell (e.g., internal warehouse) | Medium | Medium | Selling price is optional; margin section hidden until set |
| "Record Sale" button makes new users think stock decreases automatically on every count | Medium | Medium | Clear copy: "Record a sale" not "Deduct stock" |
| Reports empty state at first confuses users | High | Medium | Empty state must explain what to do ("Record your first sale to see profit") |
| Currency auto-detect fires at wrong time (locale = en_IN but user wants USD) | Low | Medium | Manual override always wins; never override a previously set preference |
| `isPro = true` hardcoded → Pro gating not tested properly in 7A | High | High | **MUST revert to `false` before any 7A build** — this is still the #1 critical blocker |

### Edge Cases

1. User records a sale for an item with `unitCost = 0` → margin = 100%, revenue = sellingPrice. Show as "Cost not set" warning.
2. User records a sale qty > currentQuantity → allow with warning (spot sales / backorders exist in real SMBs).
3. User changes sellingPrice after recording sales → historical SaleEvents must store the price at time of sale (denormalized), not reference current sellingPrice.
4. User deletes an item that has SaleEvents → SaleEvents must be preserved (or at minimum the itemName denormalized) for historical reporting.
5. User in a region with RTL script or multi-byte currency symbols — CurrencyManager.formatPrice() must handle without truncation.
6. First launch + no internet → CurrencyManager locale detection works offline (Locale.current is device-local, no network needed).

### Cheapest Experiment

Before building the full reports screen, ship only the **selling price field + profitability per item on ItemDetailView**. Run the SMB review skill on this alone. If it scores ≥ 6/10 in the profitability dimension, the margin-display approach is validated; then build the full report.

### What This Could Break Downstream

- `ExportManager.swift` — CSV export currently exports `unitCost` and `totalValue`. It will need to also export `sellingPrice`, `grossProfit`, `grossMarginPct` for completeness.
- `BulkImportView.swift` — `ImportField` enum needs a new `.sellingPrice` case so imported spreadsheets can carry selling prices.
- `ActivityEvent` types — new types `"SaleMade"` and `"MovementLogged"` must be added and handled in `ActivityEventRow.swift` display.
- Paywall gating — `SubscriptionManager` will need new capability checks: `canViewHistoricalReports` (Pro), `canExportProfitReport` (Pro).

### Post-Launch Watch Metric

Watch `profit_insight_tapped` and `report_viewed` events for the first 14 days. If < 15% of active users view Reports in week 1, the navigation placement (Decision A) needs reconsideration — reports may be too buried.

---

## HANDOFF → Designer

**Item:** Phase 7 PRD — Sales, Profitability & Reports  
**What's delivered:** This document (`phase7-prd.md`) in `smart-inventory/`  
**Acceptance criteria:** All 8 stories have acceptance criteria a QA skill can test verbatim. Decision A (navigation) and B (migration) are flagged.  
**Context:** Read `references/architecture.md` and `references/conventions.md` before designing. Existing tab bar has 5 tabs: Dashboard, Storages, Items, Audit, Profile — NOT what architecture.md says. Check running screenshot in `Stoqly_Beta_Issues/` folder for actual current UI.  
**Open questions / risks:** Decision A (Reports navigation) is the most critical for Designer to answer first. All UX flows must respect 5-tab constraint.  
**Definition of Done for Designer:** UX flows, component specs, and screen specs for all 7A stories, plus a wireframe for the Insights/Reports tab structure. Deliver as `phase7-ux-spec.md`.

---

## HANDOFF → iOS + Backend Engineers

**Item:** Phase 7 PRD — Sales, Profitability & Reports  
**What's delivered:** This document  
**Context the receiver needs:**
- Read `references/conventions.md` FIRST — critical Stoqly-specific rules
- New models needed: `SaleEvent`, `InventoryMovement`, `sellingPrice` on `InventoryItem`
- CurrencyManager already exists in `Currency.swift` — extend, don't rebuild
- VoiceInventoryView.swift has SFSpeechRecognizer infrastructure — Phase 7B will reuse it
- Anthropic API key infrastructure exists — Phase 7B AI assistant will use it
- SwiftData migration: use `= 0` defaults for new fields (Decision B above)
- ⚠️ `SubscriptionManager.isPro = true` MUST be reverted before any engineering build

**Definition of Done for Engineering:** Cursor spec written to `todolist.rtf`, covering all new models, Firestore schema, view implementations, and Firestore sync.
