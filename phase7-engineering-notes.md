# Phase 7A — Engineering Notes
**Role:** iOS Engineer + Backend Engineer  
**Date:** 2026-06-27  
**Based on:** phase7-prd.md + phase7-ux-spec.md  
**Status:** Cursor spec written to todolist.rtf (ITEM 14–38)

---

## 1. Architecture Decisions

### A. SaleEvent Model — Denormalized Design

**Decision:** Store `itemName`, `itemSKU`, `storageName`, `category` as plain `String` fields on `SaleEvent` at the time of the sale. Also hold a **soft** `@Relationship var item: InventoryItem?` (nullable) that becomes `nil` if the item is later deleted.

**Rationale:** If the item is deleted, historical revenue data must survive. Firestore also needs something to query without joining. A hard relationship with `.cascade` delete would wipe sale history when an item is removed — unacceptable for a reporting feature.

**Edge case handled:** User edits `item.sellingPrice` after recording sales — historical `SaleEvent.pricePerUnit` is a snapshot (denormalized), so old reports are unaffected.

---

### B. InventoryMovement Model — Same Denormalization Pattern

**Decision:** Same approach as SaleEvent — soft `@Relationship` to `InventoryItem?`, plus denormalized `itemName`, `itemSKU`, `storageName`, `category` strings. Includes `linkedSaleEventId: UUID?` to link movements created by Quick Sale to their parent `SaleEvent`.

**Rationale:** Movements created by `QuickSaleSheet` need a pointer to the `SaleEvent` for audit trail linkage in `ReportsView`. Storing the ID as a `UUID?` avoids a second SwiftData relationship that would complicate cascade rules.

---

### C. sellingPrice on InventoryItem — Lightweight Migration

**Decision:** Add `var sellingPrice: Double = 0` as a new stored property with a Swift default value.

**Rationale:** SwiftData handles new properties with default values via lightweight migration — no `VersionedSchema`, `MigrationPlan`, or `ModelConfiguration` changes needed. The `= 0` default means existing items gracefully get `sellingPrice = 0` (which the UI treats as "not set" / hides margin display).

---

### D. Firestore Paths

```
users/{uid}/
  storages/{storageId}/
    items/{itemId}/
      counts/{countId}               ← existing
  activityEvents/{eventId}           ← existing
  saleEvents/{saleId}                ← NEW (Phase 7A)
  inventoryMovements/{movementId}    ← NEW (Phase 7A)
```

**Why top-level under `uid` (not nested under `storages/{id}`):** SaleEvents and InventoryMovements reference items across all storages and need to be queried by date range for reports without knowing the storage ID in advance. Nesting under a specific storage would require collection group queries (extra Firestore index cost).

**Sync strategy for Phase 7A:** Push-only (fire-and-forget on create). Pull-from-cloud for `saleEvents` and `inventoryMovements` is deferred to Phase 7B when multi-device sync of sales history becomes important. Local SwiftData is the source of truth for reports in 7A.

---

### E. CurrencyManager Propagation Fix

**Root cause:** `DashboardView` was creating its own `@StateObject private var currencyManager = CurrencyManager()` (line ~21 of DashboardView.swift) independently from `InventoryAppView`, which also creates one. Two instances = two sources of truth = currency selected in Settings not reflected in Dashboard.

**Fix:** 
1. `InventoryAppView` / `MainAppContent` already creates the authoritative `CurrencyManager` `@StateObject`.
2. Remove the duplicate `@StateObject` from `DashboardView`. Replace with `@EnvironmentObject var currencyManager: CurrencyManager`.
3. `MainAppContent` already passes `.environmentObject(currencyManager)` to `DashboardView` — so this works immediately.
4. Audit all other Views that may create their own instance: `StorageDetailView`, `ValueByCategoryView`, `StorageListView`, `ItemListView`. Each should use `@EnvironmentObject`, not `@StateObject`.

---

### F. Dead Stock / Never-Audited Grace Periods

**Root cause:** The filter logic computed "dead stock" as any item where `updatedAt < 60 days ago`, without checking whether the item itself is new. An item added 5 minutes ago with `updatedAt` = now trivially passes `updatedAt < 60 days ago` = false, but the logic had a bug or the condition was weaker than intended. More importantly, "never audited" was simply `countHistory.isEmpty` — a brand-new item has no count history and was immediately flagged.

**Fix:**
- Dead stock: `item.updatedAt < sixtyDaysAgo && item.createdAt < thirtyDaysAgo`  
  (New items excluded for first 30 days)
- Never audited: `item.countHistory.isEmpty && item.createdAt < sevenDaysAgo`  
  (New items have a 7-day grace period before appearing)

---

## 2. New SwiftData Model Schemas

### SaleEvent.swift
```swift
import Foundation
import SwiftData

@Model
final class SaleEvent {
    var id: UUID
    @Relationship var item: InventoryItem?
    var itemName: String
    var itemSKU: String
    var storageName: String
    var category: String
    var quantitySold: Double
    var pricePerUnit: Double
    var costPerUnit: Double
    var notes: String
    var occurredAt: Date
    var createdAt: Date

    init(
        item: InventoryItem?,
        itemName: String,
        itemSKU: String,
        storageName: String,
        category: String,
        quantitySold: Double,
        pricePerUnit: Double,
        costPerUnit: Double,
        notes: String = "",
        occurredAt: Date = Date()
    ) {
        self.id = UUID()
        self.item = item
        self.itemName = itemName
        self.itemSKU = itemSKU
        self.storageName = storageName
        self.category = category
        self.quantitySold = quantitySold
        self.pricePerUnit = pricePerUnit
        self.costPerUnit = costPerUnit
        self.notes = notes
        self.occurredAt = occurredAt
        self.createdAt = Date()
    }

    var revenue: Double { quantitySold * pricePerUnit }
    var cogs: Double { quantitySold * costPerUnit }
    var grossProfit: Double { revenue - cogs }
    var grossMarginPct: Double? {
        guard revenue > 0 else { return nil }
        return grossProfit / revenue * 100
    }
}
```

### InventoryMovement.swift
```swift
import Foundation
import SwiftData

enum MovementTypeIn: String, CaseIterable, Codable {
    case purchase           = "Purchase"
    case transferIn         = "Transfer In"
    case returnFromCustomer = "Return from Customer"
    case adjustmentUp       = "Adjustment (Up)"
    case openingStock       = "Opening Stock"
}

enum MovementTypeOut: String, CaseIterable, Codable {
    case saleOut            = "Sale"
    case waste              = "Waste / Spoilage"
    case returnToSupplier   = "Return to Supplier"
    case transferOut        = "Transfer Out"
    case adjustmentDown     = "Adjustment (Down)"
}

@Model
final class InventoryMovement {
    var id: UUID
    @Relationship var item: InventoryItem?
    var itemName: String
    var itemSKU: String
    var storageName: String
    var category: String
    var direction: String         // "IN" or "OUT"
    var movementType: String
    var quantity: Double
    var pricePerUnit: Double
    var notes: String
    var occurredAt: Date
    var createdAt: Date
    var linkedSaleEventId: UUID?

    init(
        item: InventoryItem?,
        itemName: String,
        itemSKU: String,
        storageName: String,
        category: String,
        direction: String,
        movementType: String,
        quantity: Double,
        pricePerUnit: Double = 0,
        notes: String = "",
        occurredAt: Date = Date(),
        linkedSaleEventId: UUID? = nil
    ) {
        self.id = UUID()
        self.item = item
        self.itemName = itemName
        self.itemSKU = itemSKU
        self.storageName = storageName
        self.category = category
        self.direction = direction
        self.movementType = movementType
        self.quantity = quantity
        self.pricePerUnit = pricePerUnit
        self.notes = notes
        self.occurredAt = occurredAt
        self.createdAt = Date()
        self.linkedSaleEventId = linkedSaleEventId
    }

    var totalValue: Double { quantity * pricePerUnit }
    var isIN: Bool { direction == "IN" }
}
```

### InventoryItem additions
```swift
// Add to InventoryItem.swift after var unitCost: Double:
var sellingPrice: Double = 0

// Add to computed properties:
var grossMarginPct: Double? {
    guard sellingPrice > 0 else { return nil }
    return (sellingPrice - unitCost) / sellingPrice * 100
}

var grossProfitPerUnit: Double? {
    guard sellingPrice > 0 else { return nil }
    return sellingPrice - unitCost
}
```

---

## 3. Firestore Paths

| Collection | Path | Direction |
|-----------|------|-----------|
| Existing items | `users/{uid}/storages/{sid}/items/{iid}` | push + pull |
| Existing activity | `users/{uid}/activityEvents/{eid}` | push only |
| **New: SaleEvent** | `users/{uid}/saleEvents/{saleId}` | push only (7A) |
| **New: InventoryMovement** | `users/{uid}/inventoryMovements/{movId}` | push only (7A) |

**sellingPrice** is added to the existing item document at `users/{uid}/storages/{sid}/items/{iid}` — no new collection needed for this field.

---

## 4. New Files Created by This Spec

| File | Type | Phase |
|------|------|-------|
| `AITest/Models/SaleEvent.swift` | SwiftData `@Model` | 7A |
| `AITest/Models/InventoryMovement.swift` | SwiftData `@Model` + enums | 7A |
| `AITest/Views/QuickSaleSheet.swift` | SwiftUI Sheet View | 7A |
| `AITest/Views/MovementSheet.swift` | SwiftUI Sheet View | 7A |
| `AITest/Views/ReportsView.swift` | SwiftUI Sheet View (with NavigationStack) | 7A |
| `AITest/Views/MovementsListView.swift` | SwiftUI NavigationLink destination | 7A |

---

## 5. Modified Files

| File | Change Summary |
|------|---------------|
| `AITest/Models/InventoryItem.swift` | Add `sellingPrice`, `grossMarginPct`, `grossProfitPerUnit` |
| `AITest/Models/ActivityEvent.swift` | Add `SaleMade`, `MovementLogged` cases to display switches |
| `AITest/Models/Currency.swift` | Add locale auto-detect in `init()`, add `checkLocaleChange()` / `dismissLocaleChangeBanner()` |
| `AITest/Models/FirestoreManager.swift` | Add `pushSaleEvent()`, `pushInventoryMovement()`, add `sellingPrice` to item push/pull |
| `AITest/Views/InventoryAppView.swift` | Register new models in ModelContainer; add `safeDelete` for new models in `clearLocalData()` |
| `AITest/Views/DashboardView.swift` | Remove duplicate CurrencyManager; add Sales Performance section; add locale-change banner; fix dead stock predicates; add `@Query` for SaleEvents; add ReportsView sheet |
| `AITest/Views/EditItemView.swift` | Add Selling Price field + live margin display in Cost section |
| `AITest/Views/StorageDetailView.swift` | Add "Sale" leading swipe action; fix dark mode `.listRowBackground` |
| `AITest/Views/ItemDetailView.swift` | Add "Record Sale" button; add "Add Movement" link; add Profitability section |
| `AITest/Views/BulkImportView.swift` | Add `.sellingPrice` to `ImportField` enum + import mapping |
| `AITest/Views/SettingsView.swift` | Wrap Privacy & Ads in `#if DEBUG`; conditionally hide AI Features |
| `AITest/Views/ValueByCategoryView.swift` | Fix empty state with `ContentUnavailableView`; fix background color |
| `AITest/Views/StorageListView.swift` | Fix dark mode card backgrounds |

---

## 6. SwiftData Migration Safety

- All new fields on `InventoryItem` use `= 0` default → lightweight migration, no schema version bump needed.
- `SaleEvent` and `InventoryMovement` are entirely new `@Model` classes → additive, never destructive.
- `clearLocalData()` in `InventoryAppView` must be updated to delete `SaleEvent` and `InventoryMovement` on sign-out.
- The `ModelContainer` registration array must include `SaleEvent.self` and `InventoryMovement.self` — missing this causes a runtime crash on first query.

---

## 7. Pro Gating Summary

| Feature | Free | Pro |
|---------|------|-----|
| Record sales | ✅ | ✅ |
| Inventory movements | ✅ | ✅ |
| Profitability per item | ✅ | ✅ |
| Reports: Today / This Week / This Month / Last 30 Days | ✅ | ✅ |
| Reports: Custom date range | ❌ (paywall) | ✅ |
| Export profit report (Phase 7B) | ❌ | ✅ |

---

## 8. Analytics Events to Wire

Add these cases to `StoqlyEvent` enum in `AnalyticsManager.swift` if not already present:

```swift
case saleRecorded(itemId: String, qty: Double, sellingPrice: Double, costPrice: Double, profit: Double, storageId: String)
case movementLogged(itemId: String, movementType: String, qty: Double, pricePerUnit: Double)
case reportViewed(period: String)
case sellingPriceSet(itemId: String, source: String)
```

---

## 9. UX Spec Decisions Adopted

- **Navigation:** Reports accessible via Dashboard "Sales Performance" section → "View Full Report →" (2 taps max). No new tab. Tab bar stays at 5 tabs. (Designer Decision A resolved.)
- **Migration:** `sellingPrice = 0` default everywhere. (Decision B confirmed.)
- **KPI grid:** Revenue and Gross Profit are NOT added as new KPI grid cards (would make 8 total). They are inline stats in the Sales Performance section only. (UX spec proactive note §14.3 adopted.)
- **ReportsView:** Presented as `.sheet` (not fullScreenCover) per UX spec.
- **QuickSaleSheet and MovementSheet:** `.sheet` + `.sheetStyle()` per conventions.
- **Period sync:** ReportsView accepts `selectedPeriod: ReportPeriod` parameter so Dashboard can pass its current period selection.
