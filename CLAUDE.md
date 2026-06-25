# CLAUDE.md — Stoqly

This file is automatically read by Cursor and Claude Code at the start of every
session. Keep it current — it is the single source of truth for project conventions.

---

## App Identity

- **App name**: Stoqly
- **Bundle ID**: `com.vishuddhi.stoqly`
- **Display name**: Stoqly (Info.plist CFBundleDisplayName)
- **Xcode project**: `AITest.xcodeproj` / scheme `SmartInventory`
- **Target**: iOS 17.0+, Swift 5.9+

---

## ⚠️ Critical Coding Rules — Read Before Touching Any File

These rules exist because violations cause silent data loss or hard-to-find bugs.

### 1. Always use `safeSave`, never `try? modelContext.save()`

```swift
// ✅ correct
modelContext.safeSave(context: "addItem")

// ❌ wrong — swallows errors silently
try? modelContext.save()
```

### 2. Insert ActivityEvent BEFORE `modelContext.delete(item)`

```swift
// ✅ correct — item.storage is still valid here
let event = ActivityEvent(eventType: "ItemDeleted", itemName: item.name,
                          storageName: item.storage?.name ?? "Unknown")
modelContext.insert(event)
modelContext.safeSave(context: "delete activity")
FirestoreManager.shared.syncActivity(event)

FirestoreManager.shared.deleteItem(item)  // soft-delete in Firestore
modelContext.delete(item)                 // remove from SwiftData
modelContext.safeSave(context: "delete item")
```

### 3. Use `smartFormatted` for quantities, `%.2f` for currency only

```swift
// ✅ correct
currentQuantity = item.currentQuantity.smartFormatted  // "5" not "5.00"
unitCost        = String(format: "%.2f", item.unitCost) // "3.50"

// ❌ wrong — shows ugly trailing zeros on quantities
currentQuantity = String(format: "%.2f", item.currentQuantity)
```

### 4. Never declare structs/classes inside a `@ViewBuilder` closure

```swift
// ❌ wrong — Swift compiler error: "Closure containing a declaration
//            cannot be used with result builder 'ViewBuilder'"
var body: some View {
    struct Helper { ... }  // NOT allowed inside body
}

// ✅ correct — declare outside body, inside the View struct
struct MyView: View {
    private struct Helper { ... }  // fine here
    var body: some View { ... }
}
```

### 5. Never hardcode `isPro = true` in production paths

```swift
// ✅ correct
guard SubscriptionManager.shared.isPro else { return }

// ❌ do not ship with this
let isPro = true  // testing shortcut — must be reverted before App Store
```

### ⚠️ Pre-Ship Blockers (reminder — not yet done)
- Revert `SubscriptionManager.isPro` to `false` (currently `true` for testing)
- Remove `print("[Enrichment]...")` debug logs from `BarcodeEnrichmentService.swift`

---

## Architecture

**MVVM + SwiftData (offline-first). Firestore is the cloud sync layer, not the source of truth.**

### Data Layer — SwiftData Models (`AITest/Models/`)

| Model | Purpose |
|---|---|
| `Storage` | Warehouse / shelf / room. Cascade-deletes items. |
| `InventoryItem` | Stock item with qty, SKU, barcode, cost, UOM, category, expiry |
| `InventoryCount` | Append-only count history record per item |
| `InventoryBatch` | Individual stock lot with its own expiry date (FIFO tracking) |
| `UOM` | Unit of measure (kg, pcs, L…) |
| `ActivityEvent` | Audit log: ItemAdded, ItemUpdated, ItemDeleted, ItemCounted, StorageCreated |

Schema registered in `AITestApp.swift`:
```swift
Schema([Storage.self, InventoryItem.self, UOM.self,
        InventoryCount.self, ActivityEvent.self, InventoryBatch.self])
```

### InventoryItem Key Properties

```swift
var nearestExpiryDate: Date? // min(batches.expiryDate) ?? expiryDate
var isExpiringSoon: Bool     // uses nearestExpiryDate, within 7 days
var isExpired: Bool          // uses nearestExpiryDate
var daysUntilExpiry: Int?    // uses nearestExpiryDate
var batches: [InventoryBatch] // cascade-delete relationship
```

### ViewModel Layer (`AITest/ViewModels/`)

All ViewModels are `@MainActor final class` conforming to `ObservableObject`.

- `ItemViewModels.swift` — `ItemListViewModel`, `ItemFormViewModel`, `ItemDetailViewModel`, `CountItemViewModel`
- `StorageViewModels.swift` — `StorageListViewModel`, `StorageDetailViewModel`
- `CountViewModels.swift` — `CountViewModel`

### Manager Singletons (`AITest/Models/`)

| Manager | Responsibility |
|---|---|
| `AuthManager.shared` | Firebase Auth + Google Sign-In; publishes `isAuthenticated` |
| `FirestoreManager.shared` | Cloud sync; `syncItem`, `syncStorage`, `pullFromCloud`, `flushPending` |
| `AdManager.shared` | AdMob; call `recordCompletion(event:)` after every significant user action |
| `SubscriptionManager.shared` | StoreKit 2; exposes `isPro`, `hasRemovedAds`, `trialDaysRemaining` |
| `SpotlightManager.shared` | Core Spotlight index; `index`, `deindex`, `reindexAll` |
| `BarcodeEnrichmentService.shared` | Pro-only barcode lookup (Open Food Facts → UPCItemDB) |
| `NotificationManager.shared` | Local push notifications for low-stock and expiry alerts |

### Data Flow

1. **Writes**: ViewModel → `modelContext.insert/safeSave` → fire-and-forget `FirestoreManager.sync*()` + `SpotlightManager.index()`
2. **Reads**: Views use `@Query` for reactive SwiftData queries — never read from Firestore directly in views
3. **Cloud pull**: `pullFromCloud()` on login and on app-foreground (throttled to 15 min)
4. **Deletions**: Firestore soft-delete (`isDeleted: true`) FIRST, then `modelContext.delete()`

### Firestore Schema

```
users/{uid}/
  ├── profile:          { displayName, email, currency, lastSyncAt }
  ├── activity/{id}:    { eventType, itemName, storageName, quantityBefore/After, occurredAt }
  └── storages/{id}:    { name, location, color, isDeleted, updatedAt }
      └── items/{id}:   { name, sku, barcode, currentQuantity, unitCost, isDeleted, updatedAt }
          └── counts/{id}: { previousQty, countedQty, reason, notes, countDate }
```

---

## Monetisation

| Tier | Limits |
|---|---|
| Free | 5 storages, 30-day analytics, ad-supported |
| Pro | Unlimited storages/items, full analytics, no ads, barcode enrichment, batch expiry |
| Remove Ads | Free limits retained, ads removed |

**StoreKit product IDs:**
- `com.vishuddhi.stoqly.pro.monthly` — $2.99/month
- `com.vishuddhi.stoqly.pro.annual` — $22.99/year
- `com.vishuddhi.stoqly.removeads` — $3.99 one-time

All Pro gates: `SubscriptionManager.shared.isPro`
All ad suppression: `SubscriptionManager.shared.hasRemovedAds || isPro`
Free storage cap: **5 storages** (enforced in `StorageListViewModel.isAtFreeStorageCap`)

---

## Key Files — Read These Before Editing

| File | Why it matters |
|---|---|
| `AITestApp.swift` | App entry, AppDelegate (Firebase/FCM/Google), SwiftData container, manager injection |
| `Models/FirestoreManager.swift` | Entire sync strategy including debounce logic — read before changing sync |
| `Models/InventoryItem.swift` | All computed properties (nearestExpiryDate, isLowStock, etc.) |
| `Models/InventoryBatch.swift` | Batch expiry model |
| `Models/AdManager.swift` | Ad lifecycle and `recordCompletion(event:)` — call after every user action |
| `Models/SubscriptionManager.swift` | All StoreKit 2 entitlement logic |
| `Views/StorageDetailView.swift` | Contains `ItemDetailView`, `CountItemView`, `QuickCountView` — large file |
| `Views/InventoryAppView.swift` | Root tab view, `CountView`, `CountViewModel` |
| `ViewModels/ItemViewModels.swift` | `ItemFormViewModel.saveNew/saveEdits` — touch carefully |

---

## Concurrency Rules

- All managers are `@MainActor`
- Firestore writes are fire-and-forget `Task { }` — never `await` them in the UI path
- `@preconcurrency` imports for non-Sendable Firebase/GoogleSignIn ObjC types
- `SendableAd<T>` wrapper in `AdManager` bridges non-Sendable ad objects across actors
- Write debouncing: `syncItem` and `syncStorage` use a 1.5s cancel-and-replace Task pattern

---

## ActivityEvent Types

Use exactly these strings — they are matched in filters and Firestore queries:

```
"ItemAdded"      "ItemUpdated"    "ItemDeleted"
"ItemCounted"    "StorageCreated" "StorageDeleted"
```

---

## Maestro Test Suite

Flows live in `maestro/flows/`. Run all: `maestro test maestro/run_all.yaml`

- `appId`: `com.vishuddhi.stoqly` (not the old smartinventory ID)
- All `assertVisible` strings must use "Stoqly" branding (not "Smart Inventory")
- Current flows: 01–20 (Phase 1), 31–33 (Phase 2), 34–36 (Phase 3)

---

## Build Command

```bash
xcodebuild -project AITest.xcodeproj \
           -scheme SmartInventory \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
           build
```

Expected: exit 0, 0 errors. Only allowed warning:
`appintentsmetadataprocessor: Metadata extraction skipped. No AppIntents.framework dependency found.`

---

## Automation Results

After each Cursor task, update `automation_results.rtf` with:
- Section header matching the task
- `[COMPLETED]` or `[COMPLETED WITH ISSUES]`
- One bullet per item: what was done, which files were touched
- Build result (exit code + any new warnings)
