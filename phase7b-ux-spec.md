# UX SPEC — Phase 7B: Sales Tab, Smart Sales Entry & Reports Fix
**Role:** Product Designer
**Date:** 2026-06-27
**Builds on:** `phase7-ux-spec.md` (Phase 7A)
**Status:** READY FOR ENGINEERING

---

## 0. CEO-Approved Decisions Summary

| Decision | Outcome |
|----------|---------|
| Tab bar restructure | Profile leaves the tab bar → gear icon in Dashboard toolbar; Sales tab added at slot 4 |
| New tab bar | Dashboard (0) · Storages (1) · Items (2) · Sales (3) · Audit (4) |
| Sales tab icon | `cart.fill` |
| SmartSalesEntry | 5 modes, all Pro-only |
| ReportsView empty state | Add `.actions { }` CTA — small fix, no new screen |

---

## 1. Tab Bar Change — `InventoryAppView.swift`

### What changes in `MainAppContent.body`

**Remove:** `ProfileView()` as a `tabItem` (tag 4)

**Add:** `SalesView()` as a `tabItem` at tag 3, shift `CountView()` to tag 4.

**New tab order:**
```
Tag 0 — DashboardView     — "Dashboard"  — house.fill
Tag 1 — StorageListView   — "Storages"   — archivebox.fill
Tag 2 — ItemListView      — "Items"      — cube.box.fill
Tag 3 — SalesView         — "Sales"      — cart.fill       ← NEW
Tag 4 — CountView         — "Audit"      — list.clipboard.fill
```

**Profile access — gear icon on Dashboard:**

In `DashboardView`, add a `ToolbarItem(placement: .topBarTrailing)` gear button that opens `ProfileView` as a `.sheet`. This matches how `ReportsView` is opened from Dashboard — it stays in the navigation context without being a permanent tab.

```swift
// In DashboardView toolbar (add alongside any existing toolbar items):
ToolbarItem(placement: .topBarTrailing) {
    Button {
        showingProfile = true
    } label: {
        Image(systemName: "gearshape.fill")
            .foregroundColor(.stoqlyPrimary)
    }
    .accessibilityLabel("Settings and Profile")
    .accessibilityIdentifier("dashboardGearButton")
}
```

```swift
// In DashboardView state:
@State private var showingProfile = false

// Sheet presentation:
.sheet(isPresented: $showingProfile) {
    ProfileView()
        .environmentObject(firestoreManager)
        .environmentObject(subscriptionManager)
        .sheetStyle()
}
```

`ProfileView` already contains its own `NavigationStack` — do NOT wrap it in an extra one.

### Maestro Impact (CRITICAL)

The tab bar restructure breaks every existing Maestro flow that references tab indices 3 and 4. These flows must be updated:

- Any flow that taps "Audit" (previously tag 3) must now tap tag 4.
- Any flow that taps "Profile" (previously tag 4) must now use the gear icon path (Dashboard → gear button) instead of a tab.
- New flows for Sales tab will reference tag 3.

**Action for Cursor:** Search `maestro/flows/` for `- id: "4"` or `tabBar` index references. Flows that navigate to the Count/Audit tab must be updated from index 3 to index 4. Profile flows must be rewritten to navigate via Dashboard gear icon.

---

## 2. New Screen: `SalesView`

### Overview

`SalesView` is a top-level tab view. It gets its own `NavigationStack` (exactly as `CountView` does). Never nest a `NavigationStack` inside any sheet opened from this tab.

### File

`AITest/Views/SalesView.swift` (new file, ~200 lines)

### State

```swift
struct SalesView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject var currencyManager: CurrencyManager

    // All sale events, newest first
    @Query(sort: \SaleEvent.occurredAt, order: .reverse) private var allSales: [SaleEvent]

    @State private var showingItemPicker = false      // → SaleItemPickerSheet
    @State private var showingSmartSales = false      // → SmartSalesEntryView
    @State private var showingReports = false         // → ReportsView sheet
    @State private var preselectedItem: InventoryItem? = nil  // from picker → QuickSaleSheet
    @State private var showingQuickSale = false

    var body: some View {
        NavigationStack {
            // ... (layout below)
        }
        .sheet(isPresented: $showingItemPicker) {
            SaleItemPickerSheet(onItemSelected: { item in
                preselectedItem = item
                showingItemPicker = false
                // Defer QuickSaleSheet open to next run loop to avoid double-sheet conflict
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    showingQuickSale = true
                }
            })
            .sheetStyle()
        }
        .sheet(item: $preselectedItem, isPresented: $showingQuickSale) { item in
            // IMPORTANT: item binding via @State InventoryItem? and separate Bool
            // Use .sheet(isPresented:) with preselectedItem captured in closure
            QuickSaleSheet(item: item)
                .environmentObject(currencyManager)
                .sheetStyle()
        }
        .sheet(isPresented: $showingSmartSales) {
            SmartSalesEntryView()
                .environmentObject(subscriptionManager)
                .environmentObject(currencyManager)
                .sheetStyle()
        }
        .sheet(isPresented: $showingReports) {
            ReportsView()
                .environmentObject(currencyManager)
                .environmentObject(subscriptionManager)
                .sheetStyle()
        }
    }
}
```

**Note on sheet sequencing:** iOS does not support opening a second sheet immediately on dismiss of the first. Use `DispatchQueue.main.asyncAfter(deadline: .now() + 0.05)` to defer `showingQuickSale = true` after `showingItemPicker` dismisses. This is the established pattern in this codebase (see how `QuickCountView` hands off to `CountItemView`).

**Note on `QuickSaleSheet` presentation from picker:** Use `@State private var preselectedItem: InventoryItem?` + `@State private var showingQuickSale: Bool`. Present as `.sheet(isPresented: $showingQuickSale) { QuickSaleSheet(item: preselectedItem!) ... }` — the `preselectedItem` is guaranteed non-nil at that point because the picker only calls the callback with a valid item. Do NOT use `.sheet(item:)` here because `preselectedItem` needs to remain set while the sheet is open.

### Layout

#### Empty State (allSales.isEmpty)

```
NavigationStack
  ├── Custom header (see below)
  └── ScrollView
        └── VStack(spacing: 24)
              ├── [empty state graphic]
              │     Image(systemName: "cart.badge.plus")
              │     .font(.system(size: 64))
              │     .foregroundStyle(Color.stoqlyPrimary.opacity(0.3))
              │
              ├── Text("No sales yet")
              │     .font(.title3).fontWeight(.semibold)
              │
              ├── Text("Record a sale to start tracking your revenue and profit.")
              │     .font(.subheadline).foregroundColor(.secondary)
              │     .multilineTextAlignment(.center)
              │
              ├── Button("Record a Sale")  ← stoqlyButtonStyle()
              │     action: showingItemPicker = true
              │
              └── Button("Smart Sales Entry ✦")  ← secondary style (outlined or tinted)
                    action: showingSmartSales = true
                    .accessibilityIdentifier("smartSalesEntryButton")
```

#### Non-Empty State (allSales not empty)

```
NavigationStack
  ├── Custom header (see below)
  └── List (grouped by date, newest at top)
        Section("Today")
          SaleEventRow(sale)
          SaleEventRow(sale)
        Section("Yesterday")
          SaleEventRow(sale)
        Section("June 26")
          SaleEventRow(sale)
        ...
```

### Custom Navigation Header

```swift
// In NavigationStack content, at top of VStack:
HStack(alignment: .top) {
    VStack(alignment: .leading, spacing: 2) {
        Text("Sales")
            .font(.title2).fontWeight(.bold)
        // Today's summary if there are sales today
        if todayRevenue > 0 {
            Text("Today: \(currencyManager.formatPrice(todayRevenue))")
                .font(.caption).foregroundColor(.secondary)
        }
    }
    Spacer()
    // View Reports link
    Button {
        showingReports = true
    } label: {
        HStack(spacing: 4) {
            Text("Reports")
                .font(.caption).fontWeight(.semibold)
            Image(systemName: "chart.bar.xaxis")
                .font(.caption)
        }
        .foregroundColor(.stoqlyPrimary)
    }
    .accessibilityIdentifier("salesViewReportsButton")
}
.padding(.horizontal)
.padding(.vertical, 10)
```

### Toolbar (non-empty state)

```swift
.toolbar {
    // Smart Sales Entry — prominent, differentiated
    ToolbarItem(placement: .topBarLeading) {
        Button {
            showingSmartSales = true
        } label: {
            Label("Smart Entry", systemImage: "sparkles")
                .foregroundColor(.stoqlyAccent)
        }
        .accessibilityIdentifier("smartSalesEntryToolbarButton")
    }
    // Manual "+" for quick item picker → QuickSaleSheet
    ToolbarItem(placement: .topBarTrailing) {
        Button {
            showingItemPicker = true
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityIdentifier("salesAddButton")
    }
}
```

**Design rationale for Smart Entry placement:** In the empty state, Smart Sales Entry appears as a secondary button below the primary CTA. In the non-empty state, it becomes a toolbar button with the `sparkles` icon tinted `.stoqlyAccent` (teal) to visually differentiate it from the plain `+` button. This follows the same pattern as the Audit tab's sparkles button for SmartCountView.

### `SaleEventRow` component

```swift
struct SaleEventRow: View {
    let sale: SaleEvent
    @EnvironmentObject var currencyManager: CurrencyManager

    var body: some View {
        HStack(spacing: 12) {
            // Left: cart icon with category color stripe (or generic teal)
            Image(systemName: "cart.fill")
                .font(.callout)
                .foregroundColor(.stoqlyPrimary)
                .frame(width: 32, height: 32)
                .background(Color.stoqlyPrimaryTint)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(sale.itemName)
                    .font(.subheadline).fontWeight(.medium)
                Text("\(sale.quantitySold.smartFormatted) \(unitAbbrev) · \(timeText)")
                    .font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(currencyManager.formatPrice(sale.revenue))
                    .font(.subheadline).fontWeight(.semibold)
                // Show profit only if it was tracked
                if sale.pricePerUnit > 0 && sale.costPerUnit > 0 {
                    Text(currencyManager.formatPrice(sale.grossProfit))
                        .font(.caption2)
                        .foregroundColor(sale.grossProfit >= 0 ? .green : .red)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel("\(sale.itemName), \(sale.quantitySold.smartFormatted) sold, revenue \(currencyManager.formatPrice(sale.revenue))")
    }
}
```

`unitAbbrev`: derive from `sale.item?.uom?.symbol ?? ""` — if nil (item deleted), show empty string.
`timeText`: `sale.occurredAt.formatted(date: .omitted, time: .shortened)` — just the time within a date section.

### Date Grouping Logic

```swift
// In SalesView:
private var groupedSales: [(title: String, sales: [SaleEvent])] {
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

    var buckets: [String: [SaleEvent]] = [:]
    for sale in allSales {
        let day = cal.startOfDay(for: sale.occurredAt)
        let label: String
        if day == today { label = "Today" }
        else if day == yesterday { label = "Yesterday" }
        else {
            label = sale.occurredAt.formatted(date: .abbreviated, time: .omitted)
        }
        buckets[label, default: []].append(sale)
    }

    // Preserve display order: Today first, Yesterday second, then chronological reverse
    let order = ["Today", "Yesterday"]
    let sorted = buckets.keys.sorted { a, b in
        let ai = order.firstIndex(of: a) ?? Int.max
        let bi = order.firstIndex(of: b) ?? Int.max
        if ai != bi { return ai < bi }
        // For date strings: newest first
        return a > b
    }
    return sorted.map { label in (title: label, sales: buckets[label]!) }
}

private var todayRevenue: Double {
    let cal = Calendar.current
    return allSales
        .filter { cal.isDateInToday($0.occurredAt) }
        .reduce(0) { $0 + $1.revenue }
}
```

---

## 3. New Sheet: `SaleItemPickerSheet`

### Overview

Approximately 80 lines. Presents a searchable, scrollable list of all inventory items. User taps one → callback fires → sheet dismisses → caller opens `QuickSaleSheet` pre-filled with that item.

Analogous to `LinkExistingItemPickerSheet` in structure. Does NOT use a `NavigationStack` wrapper at the call site — this sheet contains its own `NavigationStack` for the search bar and toolbar.

### File

`AITest/Views/SaleItemPickerSheet.swift` (new file)

### Implementation

```swift
struct SaleItemPickerSheet: View {
    let onItemSelected: (InventoryItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \InventoryItem.name) private var allItems: [InventoryItem]
    @State private var searchText = ""

    private var filteredItems: [InventoryItem] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return allItems }
        return allItems.filter {
            $0.name.localizedCaseInsensitiveContains(term) ||
            $0.sku.localizedCaseInsensitiveContains(term) ||
            ($0.storage?.name.localizedCaseInsensitiveContains(term) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if allItems.isEmpty {
                    emptyInventoryState
                } else {
                    itemList
                }
            }
            .navigationTitle("Select Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .searchable(text: $searchText, prompt: "Search items or storages…")
        }
    }

    // MARK: - Empty inventory state

    private var emptyInventoryState: some View {
        ContentUnavailableView {
            Label("No Items Yet", systemImage: "cube.box")
        } description: {
            Text("Add items to your inventory first, then you can record sales against them.")
        }
    }

    // MARK: - Item list (inventory exists)

    private var itemList: some View {
        Group {
            if filteredItems.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(filteredItems, id: \.id) { item in
                    Button {
                        onItemSelected(item)
                        dismiss()
                    } label: {
                        itemRow(for: item)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityIdentifier("saleItemRow_\(item.sku.replacingOccurrences(of: "-", with: "_"))")
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func itemRow(for item: InventoryItem) -> some View {
        HStack(spacing: 12) {
            // Storage color dot
            Circle()
                .fill(Color(hex: item.storage?.color ?? "#007AFF") ?? .blue)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundColor(.primary)
                HStack(spacing: 6) {
                    Text(item.storage?.name ?? "No Storage")
                        .font(.caption2).foregroundColor(.secondary)
                    if !item.sku.isEmpty {
                        Text("· \(item.sku)")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Current stock indicator
            VStack(alignment: .trailing, spacing: 1) {
                Text(item.currentQuantity.smartFormatted)
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(item.isOutOfStock ? .red : item.isLowStock ? .orange : .secondary)
                Text(item.uom?.symbol ?? "units")
                    .font(.caption2).foregroundColor(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption2).foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .accessibilityLabel("\(item.name), \(item.currentQuantity.smartFormatted) in stock, \(item.storage?.name ?? "no storage")")
    }
}
```

### Edge Cases

**No items in inventory:** Show `ContentUnavailableView` with `Label("No Items Yet", systemImage: "cube.box")` and description directing the user to add items first. No CTA to add an item from this sheet — keeping the sheet single-purpose.

**Search returns zero results:** Use `ContentUnavailableView.search(text: searchText)` — the system-provided empty search state (iOS 17+). For iOS 16 compatibility, show a manual empty state label.

**Item is out of stock:** Row still shows, stock qty is displayed in red. This matches the Phase 7A design decision that `QuickSaleSheet` allows oversell with a warning banner.

---

## 4. New Screen: `SmartSalesEntryView`

### Overview

The landing/mode-selection screen for AI-powered bulk sales entry. Mirrors `SmartCountView` structurally but with 5 modes instead of 3, a different data output (SaleEvents instead of inventory counts), and a **Pro-only gate on all 5 modes**.

### File

`AITest/Views/SmartSalesEntryView.swift` (new file, ~220 lines)

### Key structural difference from SmartCountView

`SmartCountView` has mixed gating: free users get 3 uses/month per mode. `SmartSalesEntryView` gates ALL modes as Pro-only (no free uses). This simplifies the gating logic — every mode card checks `subscriptionManager.isPro` only.

### State

```swift
struct SmartSalesEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject var currencyManager: CurrencyManager

    @State private var showingVoice   = false
    @State private var showingPhoto   = false
    @State private var showingText    = false
    @State private var showingCSV     = false
    @State private var showingPDF     = false
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerSection
                    modeCards
                    if !subscriptionManager.isPro { proUpsellBanner }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Smart Sales Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingVoice)   { SmartSalesVoiceView().environmentObject(currencyManager).sheetStyle() }
        .sheet(isPresented: $showingPhoto)   { SmartSalesPhotoView().environmentObject(currencyManager).sheetStyle() }
        .sheet(isPresented: $showingText)    { SmartSalesTextView().environmentObject(currencyManager).sheetStyle() }
        .sheet(isPresented: $showingCSV)     { SmartSalesCSVView().environmentObject(currencyManager).sheetStyle() }
        .sheet(isPresented: $showingPDF)     { SmartSalesPDFView().environmentObject(currencyManager).sheetStyle() }
        .sheet(isPresented: $showingPaywall) { PaywallView(source: "smart_sales").sheetStyle() }
    }
}
```

**NavigationStack nesting rule:** `SmartSalesEntryView` has its own `NavigationStack`. Each mode sub-view (Voice, Photo, Text, CSV, PDF) also has its own `NavigationStack` (since they open as independent sheets). The sub-view sheets must NOT be wrapped in an extra `NavigationStack` at the call site.

### Header Section

```
VStack(spacing: 8)
  Image(systemName: "sparkles")
    .font(.system(size: 36))
    .foregroundStyle(LinearGradient([.stoqlyPrimary, .stoqlyAccent]))
  Text("Smart Sales Entry")
    .font(.title2).fontWeight(.bold)
  Text("Record multiple sales at once using voice, photo, text, or file import. AI parses the input — you review before anything is saved.")
    .font(.subheadline).foregroundColor(.secondary)
    .multilineTextAlignment(.center)
```

### Mode Cards

Each mode card uses the same `modeCard(...)` helper from `SmartCountView` but with Pro-only gating:

```swift
private func modeCard(
    icon: String,
    iconColor: Color,
    title: String,
    description: String,
    action: @escaping () -> Void
) -> some View {
    let isPro = subscriptionManager.isPro
    return Button(action: isPro ? action : { showingPaywall = true }) {
        HStack(spacing: 16) {
            // Icon bubble
            ZStack {
                Circle()
                    .fill(iconColor.opacity(isPro ? 0.12 : 0.06))
                    .frame(width: 52, height: 52)
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(isPro ? iconColor : .secondary)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(isPro ? .primary : .secondary)
                    if !isPro {
                        // Pro badge
                        Text("PRO")
                            .font(.caption2).fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.stoqlyWarning)
                            .cornerRadius(4)
                    }
                }
                Text(description)
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            if isPro {
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                Image(systemName: "lock.fill")
                    .font(.caption).foregroundColor(.stoqlyWarning)
            }
        }
        .padding(16)
        .background(Color.stoqlyCard)
        .cornerRadius(AppTheme.radiusLg)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .opacity(isPro ? 1.0 : 0.65)
    }
    .buttonStyle(PlainButtonStyle())
}
```

Mode card definitions:

```swift
private var modeCards: some View {
    VStack(spacing: 12) {
        modeCard(
            icon: "mic.fill",
            iconColor: .stoqlyPrimary,
            title: "Voice",
            description: "Say what you sold. \"5 chips, 2 waters, 1 sandwich\". AI parses into a sale list.",
            action: { showingVoice = true }
        )
        modeCard(
            icon: "camera.fill",
            iconColor: .stoqlyAccent,
            title: "Photo",
            description: "Photograph a handwritten chit, receipt, or invoice. AI reads every line.",
            action: { showingPhoto = true }
        )
        modeCard(
            icon: "text.alignleft",
            iconColor: .stoqlyInfo,
            title: "Text",
            description: "Type or paste a free-form sales list. AI structures it for you.",
            action: { showingText = true }
        )
        modeCard(
            icon: "tablecells",
            iconColor: .stoqlySuccess,
            title: "CSV / Excel",
            description: "Import a spreadsheet of sales. Map columns then confirm.",
            action: { showingCSV = true }
        )
        modeCard(
            icon: "doc.fill",
            iconColor: .orange,
            title: "PDF",
            description: "Upload a PDF invoice or sales report. AI extracts the sale rows.",
            action: { showingPDF = true }
        )
    }
    .padding(.horizontal)
}
```

### Pro Upsell Banner (free users only)

```swift
private var proUpsellBanner: some View {
    HStack(spacing: 12) {
        Image(systemName: "crown.fill")
            .foregroundColor(.stoqlyWarning)
        VStack(alignment: .leading, spacing: 3) {
            Text("Smart Sales Entry is a Pro feature")
                .font(.subheadline).fontWeight(.semibold)
            Text("Upgrade to record bulk sales with AI — saves hours of manual entry.")
                .font(.caption).foregroundColor(.secondary)
        }
        Spacer()
        Button("Upgrade") { showingPaywall = true }
            .font(.caption).fontWeight(.semibold)
            .foregroundColor(.stoqlyWarning)
    }
    .padding(14)
    .background(Color.stoqlyWarningTint)
    .cornerRadius(AppTheme.radiusMd)
    .padding(.horizontal)
}
```

**Accessibility:** Each locked mode card: `.accessibilityLabel("\(title). Pro feature. Tap to upgrade.")`. Each unlocked card: `.accessibilityLabel("\(title). \(description)")`.

---

## 5. Mode Sub-Flows — SmartSalesEntry

Each mode opens as an independent `.sheet` with `.sheetStyle()`. All 5 follow the same 3-step state machine: **Input → Parsing → Review** (then confirm → batch SaleEvents). The Review step is a unified `SaleEntryReviewView` described in Section 6.

### Mode 1 — Voice (`SmartSalesVoiceView`)

**File:** `AITest/Views/SmartSalesVoiceView.swift`

Adapted directly from `VoiceInventoryView`. Key differences:
- No storage picker (sales are not scoped to a storage at entry time)
- The "Analyse with AI" prompt is: "Parse as sales — extract item names, quantities sold, and prices if mentioned"
- After parsing, transitions to `SaleEntryReviewView` (not to inventory `EditableItem` list)
- AI call goes to a new `AIInventoryService.shared.parseSalesTranscript(transcript)` method that returns `[ParsedSaleRow]` (see Section 6 for `ParsedSaleRow`)
- Uses the same `VoiceRecordingController` and `SpeechKit` helpers — no new audio infrastructure needed

**Sub-flow steps:**
1. Record screen: microphone button, live transcript area, tip card ("say what you sold: '5 chips, 2 waters at 30 rupees each'"), usage note (Pro = unlimited)
2. Parsing screen: `ProgressView` + "Parsing sales transcript…"
3. Hands off to `SaleEntryReviewView(rows:)`

### Mode 2 — Photo (`SmartSalesPhotoView`)

**File:** `AITest/Views/SmartSalesPhotoView.swift`

Adapted from `ImageInventoryView`. Key differences:
- Camera/photo picker capture step identical to `ImageInventoryView`
- AI prompt targets sales data: "Extract all sale items from this image — look for item names, quantities, and prices on receipts, handwritten chits, or invoices"
- Output maps to `[ParsedSaleRow]` not `[ParsedInventoryItem]`
- Transitions to `SaleEntryReviewView`

**Sub-flow steps:**
1. Capture screen: camera button + photo library picker, tip card ("photograph a receipt, chit, or sales sheet")
2. Analysing screen: `ProgressView` + "Reading your image…"
3. Hands off to `SaleEntryReviewView(rows:)`

### Mode 3 — Text (`SmartSalesTextView`)

**File:** `AITest/Views/SmartSalesTextView.swift`

New lightweight view (no existing analog, but simpler than Voice/Photo).

**Sub-flow steps:**
1. Input screen:
   - Large `TextEditor` with placeholder: "Type or paste a sales list, e.g.:\n5 chips ₹10\n2 waters ₹20\n1 sandwich ₹45"
   - Tip card: same example as placeholder
   - "Parse Sales" button (`.stoqlyButtonStyle()`) — disabled when text is empty
2. Parsing screen: `ProgressView` + "Parsing your text…"
3. Hands off to `SaleEntryReviewView(rows:)`

AI call: `AIInventoryService.shared.parseSalesText(text)` → `[ParsedSaleRow]`

### Mode 4 — CSV/Excel (`SmartSalesCSVView`)

**File:** `AITest/Views/SmartSalesCSVView.swift`

Adapted from `BulkImportView` (the existing 4-step import flow). Key differences:
- `SalesImportField` enum (new, analogous to `ImportField`):
  ```swift
  enum SalesImportField: String, CaseIterable, Identifiable {
      case itemName    = "Item Name"
      case quantity    = "Quantity"
      case pricePerUnit = "Price Per Unit"
      case date        = "Date"
      case notes       = "Notes"
      case skip        = "— Skip —"
  }
  ```
- Auto-detect column headers: "item", "name", "product" → `.itemName`; "qty", "quantity", "count" → `.quantity`; "price", "rate", "unit price", "selling price" → `.pricePerUnit`; "date", "time" → `.date`
- Step 0 (Setup): file picker only — no storage selection (sales are storage-agnostic at import)
- Step 1 (Mapping): same drag-and-drop column mapping UI as `BulkImportView`
- Step 2 (Preview): first 5 rows
- Step 3 (Review): transitions to `SaleEntryReviewView` instead of `ImportResult` summary

**No pure-Swift XLSX parser needed:** Reuse the existing XLSX parser in `BulkImportView`. Extract it into a shared utility or have `SmartSalesCSVView` call the same parsing functions. Do not duplicate the XLSX decompression logic.

### Mode 5 — PDF (`SmartSalesPDFView`)

**File:** `AITest/Views/SmartSalesPDFView.swift`

New view. Uses the existing Claude multimodal integration (same as `ImageInventoryView`).

**Sub-flow steps:**
1. File picker screen:
   - `DocumentPickerView` (`.fileImporter`) with allowed content types: `[.pdf]`
   - After selection: show filename + file size, "Analyse PDF" button
   - Tip card: "Works with invoices, supplier sales sheets, or any PDF with item names and quantities"
2. Analysing screen: `ProgressView` + "Reading your PDF…" (may take 3–8 seconds for multi-page PDFs)
   - Caption: "Processing page X of Y" if page count is known
3. Hands off to `SaleEntryReviewView(rows:)`

**AI approach:** Send PDF pages as images to Claude (same multimodal pipeline as `ImageInventoryView` — convert PDF pages to `UIImage` using `PDFKit`, then call `AIInventoryService`). Cap at 10 pages; show alert "This PDF has more than 10 pages — only the first 10 will be analysed" for larger files.

---

## 6. Unified Review Screen: `SaleEntryReviewView`

### Overview

The shared final step for all 5 Smart Sales Entry modes. Presents a list of `ParsedSaleRow` objects. Each row is editable. Unresolved items (name does not match any inventory item) are highlighted. User confirms → batch `SaleEvent` insert.

### Data Model

```swift
// ParsedSaleRow — the AI output for a single detected sale line
struct ParsedSaleRow: Identifiable {
    let id: UUID = UUID()
    var itemName: String
    var quantitySold: Double
    var pricePerUnit: Double   // 0 if AI could not detect a price
    var notes: String = ""
    // Resolved at review time
    var resolvedItem: InventoryItem? = nil   // nil = unresolved
    var isSkipped: Bool = false
}
```

### File

`AITest/Views/SaleEntryReviewView.swift` (new file, ~180 lines)

### State

```swift
struct SaleEntryReviewView: View {
    @Binding var rows: [ParsedSaleRow]
    let onConfirm: () -> Void   // caller handles dismiss + toast
    let onCancel: () -> Void

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var currencyManager: CurrencyManager
    @Query private var allItems: [InventoryItem]

    @State private var isSaving = false
    @State private var linkingRowIndex: Int? = nil   // → item picker for that row

    private var unresolvedCount: Int {
        rows.filter { !$0.isSkipped && $0.resolvedItem == nil }.count
    }

    private var confirmableRows: [ParsedSaleRow] {
        rows.filter { !$0.isSkipped }
    }
}
```

### Layout

```
NavigationStack (own stack, no nesting in parent)
  Header: "Review Sales" (inline title)
  Toolbar:
    Leading: "Cancel" button → onCancel()
    Trailing: "Confirm X Sales" button (disabled if isSaving or confirmableRows.isEmpty)

  ScrollView
    VStack(spacing: 0)

      // Warning banner — unresolved items
      if unresolvedCount > 0:
        HStack
          Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
          Text("\(unresolvedCount) item\(unresolvedCount == 1 ? "" : "s") not matched to inventory")
            .font(.caption).fontWeight(.medium)
          Spacer()
          Text("Tap row to link")
            .font(.caption2).foregroundColor(.secondary)
        .padding(12)
        .background(Color.stoqlyWarningTint)
        .cornerRadius(10)
        .padding(.horizontal)

      // Row list
      List {
        ForEach($rows) { $row in
          SaleReviewRow(row: $row, allItems: allItems, currencyManager: currencyManager)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
        .onDelete { rows.remove(atOffsets: $0) }
      }
      .listStyle(.plain)

      // Bottom action area
      Divider()
      VStack(spacing: 10)
        if unresolvedCount > 0:
          Text("\(unresolvedCount) unresolved item\(unresolvedCount == 1 ? "" : "s") will still be saved — quantity will not be deducted from inventory until linked.")
            .font(.caption).foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)

        Button(isSaving ? "Saving…" : "Confirm \(confirmableRows.count) Sales") {
          Task { await saveAllSales() }
        }
        .stoqlyButtonStyle()
        .disabled(isSaving || confirmableRows.isEmpty)
        .padding(.horizontal)

        Button("Cancel") { onCancel() }
          .font(.subheadline).foregroundColor(.secondary)
      .padding(.bottom, 16)
```

### `SaleReviewRow` sub-component

```swift
struct SaleReviewRow: View {
    @Binding var row: ParsedSaleRow
    let allItems: [InventoryItem]
    let currencyManager: CurrencyManager

    @State private var showingItemPicker = false

    var isUnresolved: Bool { row.resolvedItem == nil && !row.isSkipped }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Item name + resolution status
            HStack(spacing: 8) {
                // Unresolved indicator
                if isUnresolved {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                }

                TextField("Item name", text: $row.itemName)
                    .font(.subheadline).fontWeight(.medium)

                Spacer()

                // Skip toggle
                Button(row.isSkipped ? "Undo skip" : "Skip") {
                    row.isSkipped.toggle()
                }
                .font(.caption2).foregroundColor(.secondary)
            }

            // Resolution badge
            if !row.isSkipped {
                HStack(spacing: 8) {
                    if let linked = row.resolvedItem {
                        // Resolved — shows linked item
                        Text("→ \(linked.name)")
                            .font(.caption2).fontWeight(.medium)
                            .foregroundColor(.stoqlyPrimary)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.stoqlyPrimaryTint)
                            .cornerRadius(10)
                        Button("Change") { showingItemPicker = true }
                            .font(.caption2).foregroundColor(.secondary)
                    } else {
                        // Unresolved — prompt to link
                        Button("Link to inventory item →") { showingItemPicker = true }
                            .font(.caption2).foregroundColor(.orange)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.stoqlyWarningTint)
                            .cornerRadius(10)
                    }
                    Spacer()
                }
            }

            // Qty + Price fields (hidden if skipped)
            if !row.isSkipped {
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Text("Qty")
                            .font(.caption).foregroundColor(.secondary)
                        TextField("0", value: $row.quantitySold, format: .number)
                            .font(.caption).keyboardType(.decimalPad)
                            .frame(width: 60)
                    }
                    HStack(spacing: 4) {
                        Text(currencyManager.selectedCurrency.symbol)
                            .font(.caption).foregroundColor(.secondary)
                        TextField("0.00", value: $row.pricePerUnit, format: .number)
                            .font(.caption).keyboardType(.decimalPad)
                            .frame(width: 70)
                        if row.pricePerUnit == 0 {
                            Text("(no price)")
                                .font(.caption2).foregroundColor(.orange)
                        }
                    }
                    Spacer()
                    // Revenue preview
                    if row.pricePerUnit > 0 && row.quantitySold > 0 {
                        Text(currencyManager.formatPrice(row.quantitySold * row.pricePerUnit))
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(.stoqlyPrimary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(row.isSkipped ? 0.4 : 1.0)
        .sheet(isPresented: $showingItemPicker) {
            // Reuse SaleItemPickerSheet in link mode (no quick sale follow-through)
            LinkExistingItemPickerSheet(
                parsedName: row.itemName,
                selectedStorage: nil,
                match: Binding(
                    get: {
                        if let item = row.resolvedItem { return .existing(item) }
                        return .new
                    },
                    set: { newMatch in
                        if case .existing(let item) = newMatch {
                            row.resolvedItem = item
                        } else {
                            row.resolvedItem = nil
                        }
                    }
                )
            )
            .sheetStyle()
        }
    }
}
```

### Auto-Resolution Logic

When `SaleEntryReviewView` first appears, run a name-matching pass using the existing `ItemNameMatcher`:

```swift
.onAppear {
    autoResolveRows()
}

private func autoResolveRows() {
    for index in rows.indices {
        let candidates = ItemNameMatcher.nearestMatches(query: rows[index].itemName, in: allItems, limit: 1)
        // Only auto-link if match score is high (score > 700 = exact or strong substring)
        if let best = candidates.first {
            let score = ItemNameMatcher.score(query: rows[index].itemName, candidate: best.name)
            if score >= 700 {
                rows[index].resolvedItem = best
            }
        }
    }
}
```

**Unresolved item handling at confirm time:** If a row has no `resolvedItem`, the `SaleEvent` is still saved with `item: nil` — the `SaleEvent` model already supports this via its `@Relationship var item: InventoryItem?` soft reference. The `itemName` denormalized field captures the AI-detected name. No stock deduction occurs for unresolved items (since there is no `item` to deduct from). This is intentional and matches the `SaleEvent` model design.

### Batch Save Logic

```swift
private func saveAllSales() async {
    isSaving = true
    let now = Date()

    for row in confirmableRows {
        let unitCost = row.resolvedItem?.unitCost ?? 0
        let storageName = row.resolvedItem?.storage?.name ?? "Unknown"
        let category = row.resolvedItem?.category ?? "Uncategorised"

        let event = ActivityEvent(
            eventType: "SaleMade",
            itemName: row.itemName,
            storageName: storageName,
            notes: "Smart Sales Entry batch"
        )
        modelContext.insert(event)

        let sale = SaleEvent(
            item: row.resolvedItem,
            itemName: row.resolvedItem?.name ?? row.itemName,
            itemSKU: row.resolvedItem?.sku ?? "",
            storageName: storageName,
            category: category,
            quantitySold: row.quantitySold,
            pricePerUnit: row.pricePerUnit,
            costPerUnit: unitCost,
            notes: row.notes,
            occurredAt: now
        )
        modelContext.insert(sale)

        // Deduct stock only for resolved items
        if let item = row.resolvedItem {
            let movement = InventoryMovement(
                item: item,
                itemName: item.name,
                itemSKU: item.sku,
                storageName: storageName,
                category: item.category,
                direction: "OUT",
                movementType: MovementTypeOut.saleOut.rawValue,
                quantity: row.quantitySold,
                pricePerUnit: row.pricePerUnit,
                notes: "Smart Sales Entry",
                occurredAt: now,
                linkedSaleEventId: sale.id
            )
            modelContext.insert(movement)
            item.currentQuantity -= row.quantitySold
            item.updatedAt = now
        }
    }

    // CRITICAL: Single safeSave for the entire batch
    modelContext.safeSave(context: "SmartSalesEntryBatch")

    // Sync to Firestore
    Task {
        for row in confirmableRows {
            if let item = row.resolvedItem {
                FirestoreManager.shared.syncItem(item)
            }
        }
    }

    AnalyticsManager.shared.track(.smartSalesCompleted(
        mode: "batch",
        saleCount: confirmableRows.count
    ))

    isSaving = false
    onConfirm()
}
```

**CRITICAL RULE:** Use a **single** `modelContext.safeSave(context:)` after ALL inserts. Never call `safeSave` inside the loop.

**CRITICAL RULE:** `ActivityEvent` must be inserted BEFORE any potential delete operations (not relevant here since we are only inserting/modifying, but maintain the convention for all future edits in this file).

---

## 7. Task C — `ReportsView` Empty State Fix

### What changes

In `ReportsView.swift`, the `summaryCard` computed property's empty state uses `ContentUnavailableView` but currently has no `.actions` block. This leaves new users with a dead end in Reports.

### Current code (line ~178 in ReportsView.swift)

```swift
ContentUnavailableView {
    Label("No Sales This Period", systemImage: "cart.badge.minus")
} description: {
    Text("Record sales from any item to see revenue and profit here.")
}
```

### Fixed code

```swift
ContentUnavailableView {
    Label("No Sales This Period", systemImage: "cart.badge.minus")
} description: {
    Text("Record sales from any item to see revenue and profit here.")
} actions: {
    Button("Record a Sale") {
        showSaleEntry = true
    }
    .stoqlyButtonStyle()
}
```

### Required state additions in `ReportsView`

Add to `ReportsView`'s `@State` declarations:
```swift
@State private var showSaleEntry = false
```

Add sheet presentation (alongside existing `.sheet(isPresented: $showingPaywall)`):
```swift
.sheet(isPresented: $showSaleEntry) {
    SaleItemPickerSheet(onItemSelected: { item in
        // Store item and open QuickSaleSheet after dismissal
    })
    .sheetStyle()
}
```

**Simpler alternative (recommended for Cursor — fewer sheet state variables):** Instead of full `SaleItemPickerSheet` from within `ReportsView`, use the existing pattern of navigating to the Sales tab. Since `ReportsView` is opened as a `.sheet`, it has no tab bar access. The cleanest path is to dismiss `ReportsView` then post a `NotificationCenter` notification that `SalesView` (or `InventoryAppView`) observes to open the item picker. This is consistent with how the existing `stoqly.showPaywall` notification works.

**Recommended implementation:**

```swift
// In ReportsView empty state:
Button("Record a Sale") {
    dismiss()   // dismiss ReportsView first
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        NotificationCenter.default.post(name: NSNotification.Name("stoqly.recordSale"), object: nil)
    }
}
.stoqlyButtonStyle()
```

```swift
// In SalesView (or InventoryAppView):
.onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("stoqly.recordSale"))) { _ in
    showingItemPicker = true
}
```

This avoids nested sheet complications entirely and is the same pattern as `stoqly.showPaywall`.

---

## 8. Proactive Protocol — Risks and Mitigations

### Risk 1: NavigationStack Nesting

**SalesView is a top-level tab** — it gets its own `NavigationStack`. Any sheet opened from SalesView (`SaleItemPickerSheet`, `QuickSaleSheet`, `SmartSalesEntryView`, `ReportsView`) must NOT get an additional `NavigationStack` wrapper at the call site.

The rule from the existing codebase: sheets that already contain their own `NavigationStack` (like `AddStorageView`) must never be wrapped. All new sheets in Phase 7B contain their own `NavigationStack` internally.

`QuickSaleSheet` already wraps itself in `NavigationStack` (confirmed from reading the file). Do NOT add `.sheetStyle()` wrapping with NavigationStack in the call site.

**Exception:** `SaleEntryReviewView` is NOT presented as a sheet — it is the final step inside the Voice/Photo/Text/CSV/PDF sub-flow views, which each have their own `NavigationStack`. `SaleEntryReviewView` transitions via state change (`.record → .review` step machine), not via sheet presentation.

### Risk 2: Maestro Tab Index Breakage

The tab bar restructure changes:
- Audit tab: index 3 → index 4
- Profile: removed from tab bar
- Sales: new at index 3

Maestro flows that reference tab index 3 (Audit) will silently navigate to Sales after this change. Flows that navigate to Profile (index 4) will silently go to Audit.

**Action required:** After implementing the tab bar change, update Maestro flows. Specifically search for `tabBar` index selections in `maestro/flows/`. Also update any flow that asserts "Profile" or "Settings" text via the old tab.

New Maestro flows needed for Sales tab (to be written after implementation):
- Flow 81: `81_sales_tab_empty_state.yaml` — Sales tab shows empty state, "Record a Sale" button visible
- Flow 82: `82_sales_item_picker.yaml` — Record a Sale → SaleItemPickerSheet appears with items listed
- Flow 83: `83_smart_sales_entry_pro_gate.yaml` — Smart Sales Entry button → SmartSalesEntryView → mode cards locked with PRO badge for free user

### Risk 3: SaleItemPickerSheet — No Items in Inventory

If inventory is empty when the user taps "Record a Sale" from `SalesView`, `SaleItemPickerSheet` will show `ContentUnavailableView` ("No Items Yet"). The user is stuck — they cannot add an item from within this sheet.

**This is intentional.** The spec does not add a CTA to create an item from the picker because the picker's single purpose is selection. The `ContentUnavailableView` description provides enough context: "Add items to your inventory first." This is consistent with the existing `SmartCountView` empty state for storages (which says "No storages yet — add one first" without offering an in-sheet creation flow).

If the PM decides this is a critical gap post-launch, the fix is a `NavigationLink` in the picker's empty state that opens `EditItemView` — but this risks navigation stack complexity inside a sheet and is deferred.

### Risk 4: Unresolved Items in SaleEntryReviewView

When AI parses "5 chips, 2 waters" and the inventory has "Lays Chips 30g" and "Mineral Water 500ml", the auto-resolution score may not reach the 700 threshold, leaving both rows unresolved (orange).

**Design handling:**
- `ItemNameMatcher.nearestMatches` is shown as suggestions in the `LinkExistingItemPickerSheet` when the user taps "Link to inventory item →"
- The threshold of 700 is conservative (exact match or strong substring) to avoid wrong auto-links — false links are worse than no links
- Unresolved sales still save successfully with `item: nil` — revenue is tracked, stock is not deducted
- A warning caption in the confirm area makes this explicit: "X unresolved items will still be saved — quantity will not be deducted from inventory until linked."

For the AI parsing prompt itself, include a hint to use exact inventory item names when possible. The prompt to Claude for voice/text mode should include: "Match item names as precisely as possible to common inventory item names. Prefer singular noun forms."

### Risk 5: Double-Sheet on iOS

When `SaleItemPickerSheet` dismisses and `QuickSaleSheet` opens immediately after, iOS can silently swallow the second sheet if the first has not fully animated out. The 50ms `DispatchQueue.main.asyncAfter` delay handles this for the `SalesView → SaleItemPickerSheet → QuickSaleSheet` path.

The same pattern must be used anywhere else this sequence occurs (e.g., from `ReportsView` empty state CTA via notification, then `SalesView` opening the picker, then picker selecting → QuickSaleSheet).

### Risk 6: PDF Mode — `PDFKit` Integration

`PDFKit` is not currently imported anywhere in the project. The `SmartSalesPDFView` will need:
```swift
import PDFKit
```
Page-to-image conversion:
```swift
let pdf = PDFDocument(url: pdfURL)
let page = pdf?.page(at: 0)
let image = page?.thumbnail(of: CGSize(width: 1024, height: 1400), for: .mediaBox)
```
This is CPU-bound and should run in a `Task` (already on a cooperative thread pool). Cap pages at 10 and show page-by-page progress in the analysing screen.

### Risk 7: `AIUsageManager.FeatureType` — New Cases Needed

`AIUsageManager.FeatureType` currently has `.voice`, `.image`, `.paper`. Since Smart Sales Entry is **Pro-only with no free uses**, no new `FeatureType` cases are needed — Pro-only gating bypasses `AIUsageManager` entirely. However, for analytics tracking, add a new `AnalyticsManager` event:

```swift
// In AnalyticsManager (wherever existing smart count events are defined):
case smartSalesCompleted(mode: String, saleCount: Int)
case smartSalesModeSelected(mode: String)
case smartSalesOpened
```

---

## 9. Component Summary — New Files

| File | Lines (est.) | Purpose |
|------|-------------|---------|
| `Views/SalesView.swift` | ~220 | New Sales tab — list, empty state, navigation |
| `Views/SaleItemPickerSheet.swift` | ~90 | Item picker → pre-fills QuickSaleSheet |
| `Views/SmartSalesEntryView.swift` | ~230 | Mode selection landing screen |
| `Views/SmartSalesVoiceView.swift` | ~180 | Voice mode (adapted from VoiceInventoryView) |
| `Views/SmartSalesPhotoView.swift` | ~160 | Photo/receipt mode (adapted from ImageInventoryView) |
| `Views/SmartSalesTextView.swift` | ~80 | Free-text paste mode |
| `Views/SmartSalesCSVView.swift` | ~200 | CSV/Excel import (adapted from BulkImportView) |
| `Views/SmartSalesPDFView.swift` | ~140 | PDF invoice mode |
| `Views/SaleEntryReviewView.swift` | ~180 | Unified review + confirm for all 5 modes |

### Modified Files

| File | Change |
|------|--------|
| `Views/InventoryAppView.swift` | Tab bar restructure: Sales tab added at 3, Audit at 4, Profile removed |
| `Views/DashboardView.swift` | Add gear icon toolbar button + `showingProfile` state + sheet |
| `Views/ReportsView.swift` | Add `.actions` block to empty state `ContentUnavailableView` |

---

## 10. Flows Summary — Phase 7B

```
FLOW 7: Record Sale (via SalesView)
  Entry: Sales tab → "Record a Sale" button (empty state) OR "+" toolbar button
  Steps: SaleItemPickerSheet → select item → QuickSaleSheet (pre-filled) → save
  States: no items in inventory (empty picker) / item out of stock (orange warning in QSS) / success / error

FLOW 8: Smart Sales Entry — Voice
  Entry: SalesView → sparkles toolbar → SmartSalesEntryView → Voice card
  Gate: Pro only; free users see paywall on any card tap
  Steps: Record transcript → AI parse → SaleEntryReviewView → confirm
  States: permission denied / AI error → back to record / unresolved items / success

FLOW 9: Smart Sales Entry — Photo
  Entry: SalesView → sparkles → SmartSalesEntryView → Photo card
  Steps: Camera/library capture → AI analyse → SaleEntryReviewView → confirm

FLOW 10: Smart Sales Entry — Text
  Entry: SalesView → sparkles → SmartSalesEntryView → Text card
  Steps: TextEditor input → "Parse Sales" → AI parse → SaleEntryReviewView → confirm

FLOW 11: Smart Sales Entry — CSV/Excel
  Entry: SalesView → sparkles → SmartSalesEntryView → CSV/Excel card
  Steps: File picker → column mapping → preview → SaleEntryReviewView → confirm

FLOW 12: Smart Sales Entry — PDF
  Entry: SalesView → sparkles → SmartSalesEntryView → PDF card
  Steps: PDF file picker → AI analyse (multi-page) → SaleEntryReviewView → confirm

FLOW 13: ReportsView from SalesView
  Entry: SalesView → "Reports" button in header
  Steps: ReportsView sheet → period picker → metrics
  Empty state CTA: "Record a Sale" → dismiss ReportsView → notification → SalesView picker → QuickSaleSheet

FLOW 14: Profile via Gear Icon
  Entry: Dashboard tab → ⚙️ gear icon in top-right toolbar
  Steps: ProfileView sheet → settings / subscription / export / sign out
  Exit: "Done" or swipe down
```

---

## 11. Handoff → iOS Engineer

**What's delivered:** `phase7b-ux-spec.md` in `smart-inventory/`

**Implement in this order (dependency chain):**
1. `SaleEvent` model — already exists ✅
2. `SaleItemPickerSheet` — no dependencies on other new files
3. `SalesView` — depends on `SaleItemPickerSheet` + existing `QuickSaleSheet`
4. Tab bar change in `InventoryAppView` + gear icon in `DashboardView`
5. `ReportsView` empty state fix — one-line change
6. `SaleEntryReviewView` — shared by all Smart Sales Entry modes
7. `SmartSalesEntryView` + mode sub-views (Voice/Photo/Text/CSV/PDF)
8. Maestro flow updates

**Conventions checklist for Cursor:**
- `modelContext.safeSave(context: "...")` — NEVER `try? modelContext.save()`
- `ActivityEvent` inserted BEFORE any model deletion
- `item.currentQuantity.smartFormatted` for quantities — NEVER `String(format: "%.2f", ...)`
- All money: `currencyManager.formatPrice(amount)` — NEVER hardcoded `$` or `₹`
- No `NavigationStack` inside sheets that already have one (SaleItemPickerSheet, SmartSalesEntryView, SaleEntryReviewView each have their own)
- Barcode scanner (not used here) needs `.fullScreenCover` — not relevant to this spec
- `Button` inside `Form`/`List` with non-text label needs `.buttonStyle(PlainButtonStyle())`
- All Maestro: bundle ID `com.vishuddhi.stoqly`, app name `"Stoqly"`
- Flows number from 81 onward (existing flows 1–80 must not be renumbered)

**Build verification:** After implementing, confirm:
- Tab bar shows 5 tabs: Dashboard, Storages, Items, Sales, Audit
- Profile is NOT in the tab bar
- Gear icon in Dashboard top-right opens ProfileView as a sheet
- SalesView shows empty state with "No sales yet" on a fresh account
- Tapping "Record a Sale" opens SaleItemPickerSheet
- Selecting an item from picker dismisses picker and opens QuickSaleSheet pre-filled
- ReportsView empty state shows "Record a Sale" button
- SmartSalesEntryView opens with 5 mode cards, all locked with PRO badge for free user
- Update `automation_results.rtf` after Cursor run

**Open questions for Engineering:**
1. `SmartSalesCSVView` needs to reuse the XLSX decompression logic from `BulkImportView`. Engineering decision: extract the XLSX parser into a shared utility function in `Utilities/XLSXParser.swift` so both importers share one implementation. Do NOT copy-paste 200 lines of DEFLATE code.
2. `SmartSalesPDFView` uses `PDFKit` — confirm this is already available in the project's framework list. It is an Apple framework (no third-party dependency) so it should be available without changes to the `.xcodeproj`.
3. `AnalyticsManager` — add `.smartSalesCompleted(mode:saleCount:)`, `.smartSalesModeSelected(mode:)`, `.smartSalesOpened` events, following the existing `.smartCountCompleted(mode:itemCount:)` pattern.
