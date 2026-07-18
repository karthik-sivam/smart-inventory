# UX SPEC — Phase 7: Sales, Profitability & Reports
**Role:** Product Designer  
**Date:** 2026-06-27  
**Based on PRD:** `phase7-prd.md`  
**Status:** READY FOR ENGINEERING

---

## 0. Design Decisions (PM Open Questions Resolved)

### Decision A — Reports Navigation: **Dashboard-anchored (A2 Variant)**

**Resolved:** Keep all 5 tabs unchanged: Dashboard / Storages / Items / Audit / Profile.

**Rationale:** The Audit tab hosts the time-critical Count workflow which SMBs run daily — displacing it would hurt a high-frequency job. Instead, Dashboard becomes the business intelligence hub. Users already visit Dashboard to check KPIs; Revenue and Profit belong there naturally. Reports are reachable in ≤ 2 taps from any screen (switch to Dashboard tab = 1 tap, tap "View Full Report" = 2nd tap).

**Implementation:**
- Dashboard gets 2 new KPI cards: "Revenue" + "Gross Profit" for the selected period
- A new collapsible "Sales Performance" section appears in Dashboard scrollview (between Smart Insights and Recent Activity)
- A "View Full Report →" tappable row in that section opens `ReportsView` as a `.sheet`

### Decision B — SwiftData Migration: **Default values (B2)**

**Resolved:** All new fields on existing models use `= 0` defaults. New models (`SaleEvent`, `InventoryMovement`) are purely additive. SwiftData handles this without a VersionedSchema migration. Engineering proceeds on this basis.

---

## 1. Design System Extensions (New Tokens)

These tokens extend existing Stoqly tokens — do not introduce raw hex values in code.

```
// New semantic tokens for Phase 7
color.profit.positive   = .green (system)         // profit > 0, margin > 30%
color.profit.warning    = .orange (system)        // margin 10–30%
color.profit.negative   = .red (system)           // margin < 10% or loss
color.profit.neutral    = .secondary (system)     // no selling price set
color.revenue           = .blue (system)          // revenue KPI
color.profit            = .green (system)         // profit KPI
color.cogs              = .orange (system)        // cost of goods sold

// Period picker (reusable across Dashboard + Reports)
component.periodPill    // tappable pill, selected = .primary, unselected = .secondary fill
```

New SF Symbols used:
```
cart.fill               // Sales / Record Sale
arrow.up.circle.fill    // Inventory IN
arrow.down.circle.fill  // Inventory OUT  
chart.bar.xaxis         // Reports
dollarsign.arrow.circlepath  // Revenue KPI
chart.line.uptrend.xyaxis    // Gross Profit KPI
exclamationmark.triangle.fill  // Margin alert (already in use for Low Stock — reuse)
```

---

## 2. New Component: `PeriodPicker`

Reusable across DashboardView and ReportsView.

```
COMPONENT: PeriodPicker
Renders as: horizontal scroll of pill buttons
Options: "Today" | "This Week" | "This Month" | "Custom" (Pro-gated)
Selection: .blue fill + white text; unselected = .secondarySystemFill + .label
Interaction: tap → haptic (.selection) → selected state animates with spring
Width: each pill is intrinsic content width + 20pt padding each side
Height: 36pt
Corner radius: 18pt (fully rounded)
Pro gate: "Custom" pill shows lock icon suffix when not Pro; tap → paywall sheet
```

---

## 3. New Component: `QuickSaleSheet`

Used from ItemDetailView (and optionally StorageDetailView context menu).

```
COMPONENT: QuickSaleSheet
Presentation: .sheet with .sheetStyle()
Navigation: Custom header — "Record Sale" (title, bold), "Cancel" (left, .blue), 
            "Save" (right, .blue, disabled when qty = 0)

Layout (top-down):
┌─────────────────────────────────────────────┐
│  [cancel]  Record Sale           [save]      │
├─────────────────────────────────────────────┤
│  [item photo thumbnail 44pt]                 │
│  Item Name (title2, bold)                   │
│  Storage Name (caption, secondary)           │
│  In Stock: 12 kg  ·  SKU: SKU-XXXXX        │
├─────────────────────────────────────────────┤
│  QUANTITY                                    │
│  [– stepper] [qty field, numeric] [+ stepper]│
│  Unit: kg (from item.uom.abbreviation)       │
├─────────────────────────────────────────────┤
│  SELLING PRICE                               │
│  [currency symbol] [price field, decimal]    │
│  (pre-filled from item.sellingPrice)         │
│  If sellingPrice = 0: placeholder "Enter price"│
│  + "Use default price" link if item.sellingPrice > 0│
├─────────────────────────────────────────────┤
│  DATE                                        │
│  [today's date, tappable → DatePicker]      │
├─────────────────────────────────────────────┤
│  ┌──────────────────────────────────────┐   │
│  │  Revenue: ₹X   Profit: ₹Y  Margin: Z%│   │
│  │  (live-updated; teal bg, white text)  │   │
│  └──────────────────────────────────────┘   │
│  (Hidden if sellingPrice not set)            │
├─────────────────────────────────────────────┤
│  NOTES (optional, collapsed by default)      │
│  [Tap to expand → TextField]                 │
└─────────────────────────────────────────────┘

States:
  - qty > currentQuantity → orange warning banner below quantity:
    "Selling more than in stock (have: X). Sale will record a negative stock."
    Allow → proceed; user must be aware.
  - qty = 0 → Save disabled
  - selling price = 0 and item.sellingPrice = 0 → Profit preview hidden; 
    warning caption: "No selling price — profit won't be tracked"
  - Saving → button shows spinner, fields disabled
  - Save success → haptic (.success) + dismiss + brief toast on parent: "Sale recorded"
  - Save error → alert "Failed to record sale. Check your connection."

Accessibility:
  - Quantity stepper buttons: .accessibilityLabel("Decrease quantity") / "Increase quantity"
  - Live calculation row: .accessibilityLabel("Revenue \(formatted), Profit \(formatted), Margin \(pct)%")
  - All text fields have .accessibilityLabel with field purpose
```

---

## 4. New Component: `MovementSheet`

```
COMPONENT: MovementSheet
Presentation: .sheet with .sheetStyle()
Navigation: Custom header — "Add Movement" (title, bold), "Cancel" (left), "Add" (right, disabled if qty = 0)

Layout:
┌─────────────────────────────────────────────┐
│  [cancel]  Add Movement           [add]      │
├─────────────────────────────────────────────┤
│  DIRECTION                                   │
│  [Segmented: IN | OUT]                       │
│  (changes type options below)               │
├─────────────────────────────────────────────┤
│  TYPE                                        │
│  [Picker / Menu — see type lists below]     │
├─────────────────────────────────────────────┤
│  ITEM  (if opened from a non-item context)   │
│  [Item picker — future; 7B]                 │
│  (7A: always launched from ItemDetailView)  │
├─────────────────────────────────────────────┤
│  QUANTITY                                    │
│  [qty field, numeric]  [unit abbreviation]  │
├─────────────────────────────────────────────┤
│  PRICE PER UNIT (optional)                  │
│  Label changes by type:                     │
│  Purchase → "Purchase Price per Unit"       │
│  Waste → "Wasted Value per Unit"            │
│  Other → "Price per Unit (optional)"        │
├─────────────────────────────────────────────┤
│  DATE  [today, tappable → DatePicker]       │
├─────────────────────────────────────────────┤
│  NOTES [TextField, optional]                │
└─────────────────────────────────────────────┘

IN types (picker options):
  📦 Purchase          (default for IN)
  ↩️  Return from Customer
  ➡️  Transfer In
  ⬆️  Adjustment (Up)
  🏁 Opening Stock

OUT types (picker options):
  🛒 Sale              (taps through to QuickSaleSheet instead)
  🗑️  Waste / Spoilage  (default for OUT)
  ↩️  Return to Supplier
  ➡️  Transfer Out
  ⬇️  Adjustment (Down)

Note: "Sale" in OUT types is a shortcut — tapping it dismisses MovementSheet and 
      opens QuickSaleSheet. This keeps Sale as the primary flow.

States:
  - qty = 0 → Add disabled
  - success → haptic (.success) + toast "Movement recorded"
  - error → alert

Accessibility:
  - Direction segment: .accessibilityLabel("Movement direction")
  - Type picker: .accessibilityLabel("Movement type")
```

---

## 5. Modified Screen: `EditItemView` — Selling Price Field

```
SCREEN MODIFICATION: EditItemView
Change: Add "Selling Price" field and live margin display

Insert after "Unit Cost" field:

  ┌──────────────────────────────────────────┐
  │  Selling Price                     [₹ ██] │  ← TextField, decimal keyboard
  │  Margin: 33%  ●green / ●orange / ●red     │  ← caption, live-calculated
  └──────────────────────────────────────────┘
  
  Margin color logic:
    > 30%: .green (good)
    10–30%: .orange (acceptable)
    < 10%: .red (low margin warning)
    Selling price = 0 or not set: hidden (no placeholder, no 0%)
    Selling price < unit cost: .red + "Selling below cost" warning caption

  The field is optional. If left blank / 0, it saves as sellingPrice = 0.
  
  Accessibility: .accessibilityLabel("Selling price per unit")
  
  BulkImport: ImportField enum gets new case .sellingPrice = "Selling Price"
  Auto-detected column headers: ["selling price", "sale price", "mrp", "retail price", "price"]
```

---

## 6. Modified Screen: `ItemDetailView` — Profitability Section

```
SCREEN MODIFICATION: ItemDetailView
Change: Add "Profitability" card section between the stock stats and count history

STATE A: Selling price set
┌──────────────────────────────────────────┐
│  💰 PROFITABILITY                         │
│  ────────────────────────────────────────│
│  Cost          ₹100.00                   │
│  Selling Price ₹150.00                   │
│  ─────────────────────────────────────── │
│  Profit/unit   ₹50.00         (green)    │
│  Gross Margin  33%            (green)    │
└──────────────────────────────────────────┘

Margin color matches Edit form rules (>30% green, 10-30% orange, <10% red, loss = red)
Section uses .listRowBackground(Color(.secondarySystemGroupedBackground))
— or equivalent for the card style already in use

STATE B: No selling price set
┌──────────────────────────────────────────┐
│  💰 PROFITABILITY                         │
│  ────────────────────────────────────────│
│  Set a selling price to track your       │
│  profit margin for this item.            │
│  [Set Selling Price →]  ← .blue link     │
└──────────────────────────────────────────┘
Tapping "Set Selling Price" opens EditItemView pre-scrolled to selling price field.

NEW BUTTON in ItemDetailView action area:
Add "Record Sale" button alongside existing actions:
  Existing: Edit, Quick Count (maybe others)
  New: "Record Sale" (cart.fill icon, .green tint)
  Placement: In the same horizontal action button row, or as a prominent card button
  
  If item.currentQuantity == 0:
    Button still shows but is dimmed (not disabled — allow backorders)
    Shows caption "Out of stock — sale will create negative stock"

ALSO ADD: "Add Movement" as a secondary action (text link / small button below main actions):
  "Add Movement ↗" — opens MovementSheet
```

---

## 7. Modified Screen: `StorageDetailView` — Sale Swipe Action

```
SCREEN MODIFICATION: StorageDetailView item rows
Change: Add "Sale" as a leading-edge swipe action alongside "Count"

Current leading swipe: Count (green, left-to-right)
New: Count REPLACES with dual leading actions — but iOS .swipeActions(edge: .leading) 
     allows multiple buttons:
     
     Swipe right on item row:
     [Count ✓ green] [Sale 🛒 teal]
     
     Tapping "Sale" → opens QuickSaleSheet(item: item) as sheet

Note to engineering: Keep Count as the first (outermost) button since it's the most frequent action.
```

---

## 8. Modified Screen: `DashboardView` — Business Performance Section

```
SCREEN MODIFICATION: DashboardView
Changes: 2 new KPI cards + new Sales Performance section

KPI GRID (2 new cards added to existing 6, making 8 total):
  New card 1: "Revenue"
    value: currencyManager.formatPrice(revenue for selected period)
    icon: "dollarsign.arrow.circlepath"
    gradient: AppTheme.kpiGradients[6] (new — blue-teal gradient)
    delta: "+X% vs last period" when comparable data exists
    action: opens ReportsView
    
  New card 2: "Gross Profit"  
    value: currencyManager.formatPrice(grossProfit for selected period)
    icon: "chart.line.uptrend.xyaxis"
    gradient: AppTheme.kpiGradients[7] (new — green gradient)
    delta: margin % — e.g., "32% margin"
    action: opens ReportsView
    IF grossProfit < 0: gradient uses red tones, icon = "chart.line.downtrend.xyaxis"

NEW SECTION "Sales Performance" (insert between Smart Insights and Recent Activity):

┌──────────────────────────────────────────┐
│  Sales Performance          [Today ▾]    │  ← Period picker (PeriodPicker component)
│  ─────────────────────────────────────── │
│  [Mini bar chart: 7 bars, last 7 days]   │  ← CountTrendChart reused/adapted
│  Revenue ₹X   Profit ₹Y   Margin Z%     │
│  ─────────────────────────────────────── │
│  View Full Report →           [chevron]  │  ← Opens ReportsView as .sheet
└──────────────────────────────────────────┘

Empty state (no sales yet):
┌──────────────────────────────────────────┐
│  Sales Performance                       │
│  ─────────────────────────────────────── │
│  No sales recorded yet.                  │
│  Start recording sales to see your       │
│  profit insights here.                   │
│  [Record Your First Sale →]              │  ← Opens item picker → QuickSaleSheet
└──────────────────────────────────────────┘

This section is hidden for new users who have 0 items AND 0 sales (don't clutter onboarding).
It appears as soon as ≥1 item has a sellingPrice OR ≥1 SaleEvent exists.
```

---

## 9. New Screen: `ReportsView`

```
SCREEN: ReportsView
Flow: Dashboard → "View Full Report →" → sheet
Presentation: .sheet with .sheetStyle() OR fullScreenCover
              Recommendation: .sheet (preserves context, user can dismiss)
Navigation: Custom header — "Reports" (bold title), "Done" (right, dismisses)
Platform: iOS only

LAYOUT:
┌──────────────────────────────────────────┐
│  Reports                          [Done] │
│  ─────────────────────────────────────── │
│  [PeriodPicker: Today|Week|Month|Custom] │
│  ─────────────────────────────────────── │
│                                          │
│  SUMMARY CARD                            │
│  ┌──────────────────────────────────┐   │
│  │ Revenue    COGS    Profit  Margin│   │
│  │  ₹8,400   ₹5,200   ₹3,200  38% │   │
│  │ [=======revenue bar==========]   │   │
│  │ [===cogs bar=========]           │   │
│  │ [==profit bar====]               │   │
│  └──────────────────────────────────┘   │
│                                          │
│  REVENUE TREND                           │
│  [Bar chart: daily/weekly bars]          │
│  [x-axis: dates, y-axis: ₹ values]      │
│                                          │
│  TOP ITEMS BY REVENUE                    │
│  [ranked list: name, qty sold, revenue]  │
│  1. Prawn — 12 kg — ₹4,800             │
│  2. Chicken — 8 kg — ₹2,400            │
│                                          │
│  MARGIN ALERTS  (if any items < 10%)     │
│  ┌──────────────────────────────────┐   │
│  │ ⚠️ 2 items with low margin        │   │
│  │ Salt — 2% margin (below cost!)   │   │
│  │ Sugar — 5% margin                │   │
│  └──────────────────────────────────┘   │
│                                          │
│  INVENTORY MOVEMENTS (collapsible)       │
│  IN this period:   +450 units, ₹12,000  │
│  OUT this period:  −120 units            │
│    ↳ Sales: −80    Waste: −40            │
│  [View All Movements →]                  │
└──────────────────────────────────────────┘

STATES:
  Loading: skeleton shimmer on summary card and chart
  
  Empty (no sales in period):
    ContentUnavailableView {
      Label("No Sales This Period", systemImage: "cart.badge.minus")
    } description: {
      Text("Record sales from any item to see revenue and profit here.")
    } actions: {
      Button("How to Record a Sale") { showingSaleHelp = true }
    }
  
  Pro gate (Custom period, free user):
    "Custom" period pill shows lock icon
    Tapping → PaywallView sheet
    Periods Today/Week/Month still work for free users
    Historical data > 30 days is blurred with Pro badge overlay
  
  Offline:
    Data shown from local SwiftData (SaleEvents sync to Firestore but local-first)
    No banner needed — offline-first works transparently
  
  Error loading:
    Banner: "Could not load report data. Pull to refresh."

CHART SPEC:
  Daily bars: when period = "Today" or "This Week"
  Weekly bars: when period = "This Month"
  Bar color: .blue (revenue), with .green overlay for profit portion
  Reuse `CountTrendChart` pattern from existing Components/ for consistency
  Chart library: Swift Charts (already in use in app — check DashboardView for import)

COPY:
  Title: "Reports"
  Section headers: "Summary" / "Revenue Trend" / "Top Items by Revenue" / "Margin Alerts" / "Movements"
  Empty state: "No Sales This Period" / "Record sales from any item to see revenue and profit here."
  Pro badge text: "Pro feature — upgrade to view custom date ranges"

DARK MODE:
  Summary card uses Color(.secondarySystemGroupedBackground) — adapts automatically
  Bar chart: uses system blue/green (adapts)
  Margin alert card: Color(.systemOrange).opacity(0.15) background — adapts in dark mode
  Never hardcode hex colors — use all system semantic colors

ACCESSIBILITY:
  Period picker: .accessibilityLabel("Report period selector")
  Summary card: .accessibilityElement(children: .combine) → reads all four metrics together
  Chart: .accessibilityLabel("Revenue chart for [period]. Highest day: [date] at ₹[amount].")
  Each top item row: .accessibilityLabel("[Name], [qty] sold, revenue [amount]")
  Pro lock: .accessibilityLabel("Custom period. Pro feature.")

LOCALIZATION:
  All monetary values through currencyManager.formatPrice()
  Dates through DateFormatter with .medium style (handles locale automatically)
  No hardcoded date format strings
```

---

## 10. New Screen: `MovementsListView` (secondary, from ReportsView)

```
SCREEN: MovementsListView
Flow: ReportsView → "View All Movements →"
Presentation: NavigationLink inside ReportsView (stays in the sheet stack)
Navigation: Custom header — "Movements" + "Back" + period display

LIST ITEM:
  ┌────────────────────────────────────────┐
  │  [UP▲ green / DOWN▼ red icon]          │
  │  Purchase · 5 kg        Jun 27, 2:30PM │
  │  Prawn  ·  ₹200/unit    +₹1,000 value │
  └────────────────────────────────────────┘

Filter: Same PeriodPicker as Reports (inherits selected period)
Group by date (section headers: "Today", "Yesterday", "June 26", etc.)

Empty state:
  ContentUnavailableView {
    Label("No Movements", systemImage: "arrow.up.arrow.down.circle")
  } description: { Text("Movements recorded from Item Detail will appear here.") }
```

---

## 11. Currency: Auto-Detect Flow

```
FLOW: Currency Auto-Detection (first install + locale change)

FIRST INSTALL:
  CurrencyManager.init() checks UserDefaults for saved currency.
  If NOT found (first install):
    → Read Locale.current.currency?.identifier (no network needed)
    → Find matching Currency in Currency.currencies by code
    → If found: set selectedCurrency = match (silently, no alert)
    → If not found: fall back to USD
    → Save to UserDefaults
  User does NOT see a prompt — just the correct currency at launch.

LOCALE CHANGE DETECTION:
  In InventoryAppView or AppDelegate:
  → On .scenePhase change to .active (foreground):
    → Re-read Locale.current.currency?.identifier
    → Compare to currentlySavedCurrency.code
    → If DIFFERENT and user has NOT dismissed this locale's prompt before:
      → Show banner (NOT an alert — less disruptive):

  BANNER (appears at top of Dashboard, below nav header):
  ┌──────────────────────────────────────────┐
  │  📍 Your region changed to India         │
  │  Switch to Indian Rupee (₹)?            │
  │  [Switch to ₹]        [Keep USD]        │
  └──────────────────────────────────────────┘
  
  "Switch to ₹" → updates CurrencyManager.selectedCurrency
  "Keep USD" → saves a flag: "dismissed_locale_change_INR" so this prompt never shows again
  
  Banner auto-dismisses after 8 seconds if not tapped (defaults to "keep current").
  
  NEVER show this prompt:
  - If the user has previously manually selected a currency in Settings (override flag)
  - If locale change is detected < 24h after the last detection (debounce)
  - More than once per locale change

CONSISTENCY FIX (Bug Sprint overlap):
  CurrencyManager is created as @StateObject in InventoryAppView (root)
  → passed as .environmentObject() at root level
  → All child views (including StorageDetailView, ValueByCategoryView, ItemDetailView)
     receive it via @EnvironmentObject
  → All monetary display uses currencyManager.formatPrice() ONLY — no hardcoded $ signs
  → Audit trail: grep for '"$"' and '"%.2f"' to find non-compliant spots
```

---

## 12. Dark Mode Fixes (Bug Sprint — UX Spec)

These are the bugs visible in the `Stoqly_Beta_Issues/` screenshots.

### Bug 1: Value by Category — Empty State (Light + Dark)
```
CURRENT: Shows only "Total ₹0.00" text floating in center of a huge blank sheet.
         In dark mode, the sheet background merges with the app background — looks broken.

FIX SPEC (ValueByCategoryView.swift):
  When items.isEmpty OR all items have unitCost = 0:
    Replace blank area with ContentUnavailableView:
    
    ContentUnavailableView {
      Label("No Category Values", systemImage: "chart.pie")
    } description: {
      Text("Add items with a unit cost to see your inventory value by category.")
    }
    
  In dark mode:
    The sheet itself uses .background(Color(.systemGroupedBackground))
    which is NOT pure black — it's a slightly elevated dark gray.
    Fix: Remove any explicit .background(Color.gray.opacity(0.1)) or similar
    that is causing the flat appearance. Use .systemGroupedBackground consistently.
```

### Bug 2: Storage Row Dark Mode (StorageListView + StorageDetailView)
```
CURRENT: Storage row card background = same black as page background in dark mode.
         Rows are invisible — no visual separation.

FIX SPEC:
  Storage rows use .listRowBackground(Color(.secondarySystemGroupedBackground))
  — this is NOT pure black in dark mode; it is a slightly lighter elevated surface.
  
  In StorageListView: Each storage card should use:
    .background(Color(.secondarySystemGroupedBackground))
    .cornerRadius(12)
  
  In StorageDetailView (item rows in List):
    .listRowBackground(Color(.secondarySystemGroupedBackground))
  
  Both fixes use Apple's semantic colors — they adapt correctly in all modes.
  Do NOT use Color(.systemBackground) for cards — it's the same as page background.
  Use Color(.secondarySystemGroupedBackground) or Color(.tertiarySystemBackground) for elevation.
```

### Bug 3: Dead Stock / Never Audited — Time Logic
```
CURRENT: "Possible dead stock" and "Never audited" show items added just minutes ago.

FIX SPEC (DashboardView.swift smart insights logic):

  Possible dead stock (items not touched in 60+ days):
    CURRENT: items where updatedAt < now - 60 days
    FIX: items where updatedAt < now - 60 days AND createdAt < now - 30 days
    (Grace period: new items are excluded for 30 days after creation)

  Never audited (items never counted):
    CURRENT: items with empty countHistory
    FIX: items with empty countHistory AND createdAt < now - 7 days
    (Grace period: new items have 7 days before they appear in "never audited")
    
  Rationale: An item added 2 minutes ago logically hasn't had time to be counted. 
  Showing it as "never audited" immediately creates noise and erodes trust in insights.
```

### Bug 4: Settings — Hide Ad Tracking and API Key Rows
```
CURRENT: "Privacy & Ads" section shows "Ad Tracking" and "Ad Tracking Settings" rows.
         "AI Features" section shows "Anthropic API Key" row — confusing for end users.

FIX SPEC (SettingsView.swift):

  Ad Tracking section:
    Hide the entire "Privacy & Ads" section from public Settings.
    The ATT permission dialog appears automatically on first use — users don't need
    manual tracking settings. Showing "Ad Tracking: Not yet requested" creates confusion
    and looks unpolished.
    
    CONDITION to hide: always hide from the Settings sheet
    (Internal debug settings can be shown in Debug builds via #if DEBUG if needed)

  Anthropic API Key row:
    The API key row (AIAPIKeyRow) is a developer/power-user setting.
    Move to a hidden "Developer Settings" section, revealed only by tapping the 
    version number 5 times (standard iOS developer menu pattern).
    
    DEFAULT STATE: "AI Features" section does NOT appear in Settings for users who 
    have the key configured via Secrets.plist (they don't need to see it).
    
    CONDITION to show: only if SecretsManager.anthropicAPIKey == nil 
    (key not in Secrets.plist) AND user has explicitly opted in to AI features.
    
    SHORT TERM FIX (simpler): Just move AIAPIKeyRow into the ABOUT section,
    rename to "AI Settings" with a subtle description, and hide if key is configured.
    Show the Ad Tracking section only in #if DEBUG builds.
```

### Bug 5: Currency Inconsistency
```
CURRENT: StorageDetailView total value shows ₹, but item row prices show $.
         Root cause: some views create their OWN CurrencyManager() instead of 
         receiving it as @EnvironmentObject.

FIX SPEC:
  1. InventoryAppView creates ONE CurrencyManager @StateObject at root
  2. Passes it .environmentObject(currencyManager) to ALL tabs
  3. Every view that shows prices uses @EnvironmentObject var currencyManager: CurrencyManager
  4. Grep for all uses of String(format: "%.2f", amount) in Views/ — each one 
     must be replaced with currencyManager.formatPrice(amount)
  5. Grep for hardcoded "$" currency symbol — replace with currencyManager.selectedCurrency.symbol
  
  Files known to need audit: StorageDetailView.swift, ValueByCategoryView.swift,
  DashboardView.swift (already correct), InventoryAppView.swift (to propagate root manager)
```

---

## 13. Flows Summary (All Phase 7A)

```
FLOW 1: Set Selling Price
  Entry: EditItemView → "Selling Price" field
  Steps: Open item edit → fill Selling Price → see live margin → Save
  Exits: Saved (item updated) / Cancelled (no change)
  States: margin positive (green) / warning (orange) / loss (red) / unset (hidden)

FLOW 2: Quick Sale
  Entry: ItemDetailView → "Record Sale" button
  Entry: StorageDetailView → swipe right → "Sale" action
  Steps: QuickSaleSheet → qty → price (pre-filled) → date → confirm
  Exits: Saved (stock deducted, SaleEvent created) / Cancelled
  States: qty > stock (orange warning) / no price (hidden profit) / saving / success / error

FLOW 3: Add Inventory Movement
  Entry: ItemDetailView → "Add Movement" link
  Steps: MovementSheet → IN/OUT → type → qty → price (optional) → date → add
  Exits: Saved (stock adjusted, InventoryMovement created) / Cancelled
  States: qty = 0 (disabled) / Sale type (routes to Flow 2) / success / error

FLOW 4: View Reports
  Entry: Dashboard → "Sales Performance" section → "View Full Report →"
  Steps: ReportsView sheet → period picker → scroll metrics / chart / items / alerts
  Entry 2: Dashboard → Revenue KPI card → tap → opens ReportsView
  Exits: "Done" dismiss
  States: loading / empty / data / pro-gate (for custom) / offline / error

FLOW 5: View All Movements
  Entry: ReportsView → "View All Movements →"
  Steps: MovementsListView → filter by period → scroll
  Exits: Back to ReportsView

FLOW 6: Currency Auto-Detect
  Entry: First app launch (new install)
  Steps: Auto (no UI) → detects locale → sets currency
  Entry 2: App returns to foreground after device locale change
  Steps: Banner appears on Dashboard → "Switch" or "Keep" → resolved
  Exits: Currency changed / kept (banner dismissed)
```

---

## 14. Beyond the Ask (Proactive Protocol)

### Usability Risks

1. **"Record Sale" discoverability.** It's a new concept. First-time users may not realize that recording a sale deducts stock. The QuickSaleSheet copy must be explicit: "Records a sale AND deducts [qty] from stock." Consider a one-time tooltip on the "Record Sale" button (use `@AppStorage("hasSeenSaleTip")` flag pattern, already used for count tips).

2. **Margin display anxiety.** Showing "Selling below cost! — LOSS" in red on a café owner's entire protein inventory could cause panic without context. Add a tooltip/explainer: "This compares your unit cost to your selling price. If cost changes, update it in Edit Item."

3. **8 KPI cards is too many.** The dashboard currently has 6 KPI cards. Adding 2 more = 8 cards in a 2-column grid = 4 rows of cards before you even reach Inventory Health. This is overwhelming. **Alternative:** Do NOT add Revenue + Profit as separate KPI cards in the grid. Instead, put them at the top of the new "Sales Performance" section as 2 inline stats. This keeps the KPI grid at 6 (visual consistency preserved).

4. **Period mismatch.** Dashboard KPI period (e.g., "This Month") vs Reports screen period should stay in sync. If user picks "This Week" on Dashboard, ReportsView should open defaulting to "This Week." This requires passing the period selection as a parameter to ReportsView, not defaulting to a hardcoded value.

### Riskiest Assumption to Test

The riskiest assumption is that SMB owners will **proactively record sales in the app.** Many restaurant owners use a POS system (Square, Razorpay) for actual sales and might not want double-entry. We're assuming they don't have POS or are willing to use Stoqly as their primary sales record.

**Test:** In the post-7A TestFlight notes, add: "Now you can record sales directly in Stoqly! 🎉" and track how many beta users actually record ≥ 1 sale in the first week. If < 20%, the friction of manual entry is too high — that's when voice entry (Phase 7B) becomes urgent.

### Performance on Low-End Devices

- ReportsView aggregates SaleEvents for a period — if a user has 1,000+ sales over a year, this query could be slow. Filter SaleEvents by `occurredAt` date range at SwiftData level, not in memory.
- Bar chart for "This Month" = 30 bars = acceptable. Never show > 90 bars (quarter) in Phase 7A — add a "Show by week" toggle for Month view if needed.
- `MovementsListView` with 500+ movements: use `@Query` with a sort descriptor and lazy loading (List already lazy in SwiftUI). Do NOT load all movements into an array.

### Design System Inconsistency to Watch

- The `PeriodPicker` component (new) must visually match the filter chips in `CountViewModel.StatusFilter` (the "Due / Uncounted / Low Stock / All" pills in the Audit tab). If they look different, the app feels inconsistent. Engineering should extract both into the same reusable component or at minimum match the spacing/typography tokens exactly.

---

## HANDOFF → iOS Engineer + Backend Engineer

**Item:** Phase 7 UX Spec  
**What's delivered:** This document (`phase7-ux-spec.md`) in `smart-inventory/`  
**Acceptance criteria:** Every screen spec has a defined empty state, error state, and success state. All new components are described with exact layout and behavior.  
**Context the receiver needs:**
- Use `Color(.secondarySystemGroupedBackground)` for card backgrounds — NOT raw hex, NOT gray
- All monetary display: `currencyManager.formatPrice(amount)` — never hardcode symbol
- New entry point: "Record Sale" button on ItemDetailView + leading swipe action on StorageDetailView
- `QuickSaleSheet` and `MovementSheet` present as `.sheet { ... .sheetStyle() }`
- `ReportsView` also presents as `.sheet` (not fullScreenCover)
- Chart: reuse Swift Charts pattern from existing Dashboard (CountTrendChart or CategoryBarChart)
- `PeriodPicker` must visually match existing Audit tab filter chips
- Read `references/conventions.md` first — safeSave, ActivityEvent ordering, etc. all apply

**Open questions for Engineering:**
1. Does `SaleEvent.item` use a SwiftData `@Relationship` to `InventoryItem`? If item is deleted, what happens to historical SaleEvents? Recommendation: soft relationship + denormalize `itemName` and `itemSKU` as strings on SaleEvent. Engineering decides.
2. Should `InventoryMovement` have a relationship to `SaleEvent` (so "Sale" movement and SaleEvent are linked)? Or separate? Engineering decides.

**Definition of Done for Engineering:** All 7 flows implemented as described, all screen specs match this document's states, QA can test every acceptance criterion from the PRD.
