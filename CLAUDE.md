# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Smart Inventory** — an iOS SwiftUI inventory management app for SMBs.
- Bundle ID: `com.vishuddhi.smartinventory`
- Target: iOS 17.0+, Swift 5.9+
- Xcode project: `AITest.xcodeproj` (display name is "Smart Inventory")

## Build & Run

This is an Xcode project with no command-line build scripts. All building, testing, and running is done through Xcode.

- **Build**: Open `AITest.xcodeproj` in Xcode → ⌘B
- **Run on simulator**: ⌘R
- **Unit tests**: ⌘U (targets: `AITestTests`, `AITestUITests`)
- **StoreKit testing**: Assign `SmartInventory.storekit` to the Run scheme in Xcode for local IAP testing without App Store

## Architecture

**MVVM + SwiftData (offline-first) with Firestore as cloud sync layer.**

### Data Layer

SwiftData `@Model` classes are the single source of truth for the UI:

- `Storage` — represents a warehouse/room/shelf; cascade-deletes its `InventoryItem` children
- `InventoryItem` — individual items with quantity, SKU, barcode, cost, UOM relationship
- `InventoryCount` — count history records (cascade-deleted with item)
- `UOM` — units of measurement
- `Currency` — supported currencies (static, not a SwiftData model)

All SwiftData models live in `AITest/Models/`. Container is configured in `AITestApp.swift` with schema `[Storage, InventoryItem, UOM, InventoryCount]`.

### ViewModel Layer (`AITest/ViewModels/`)

All ViewModels are `@MainActor ObservableObject`:

- `ItemViewModels.swift` — `ItemListViewModel`, `ItemFormViewModel`, `ItemDetailViewModel`, `CountItemViewModel`
- `StorageViewModels.swift` — `StorageListViewModel`, `StorageDetailViewModel`
- `CountViewModels.swift` — `CountViewModel`

### Manager Singletons (`AITest/Models/`)

- `AuthManager.shared` — Firebase Auth + Google Sign-In; publishes `isAuthenticated`, `currentUser`
- `FirestoreManager.shared` — cloud sync; exposes `syncState`, `pullFromCloud()`, `pushAllToCloud()`
- `AdManager.shared` — AdMob banner/interstitial/reward ads; call `recordCompletion(event:)` after user actions
- `SubscriptionManager.shared` — StoreKit 2; exposes `isPro`, `hasRemovedAds`

### Data Flow

1. **Writes**: ViewModel → `modelContext.insert/save` (SwiftData) → fire-and-forget `FirestoreManager.sync*()` async task
2. **Reads**: Views use `@Query` macros for reactive SwiftData queries; never read from Firestore directly
3. **Cloud pull**: `pullFromCloud()` on login and pull-to-refresh; merges via last-write-wins on `updatedAt`
4. **Deletions**: Soft-delete pattern — Firestore `isDeleted: true` first, then `modelContext.delete()`

### Firestore Schema

```
users/{uid}/
  ├── profile: { displayName, email, currency, ... }
  ├── storages/{id}: { name, location, color, isDeleted, updatedAt, ... }
  │   └── items/{id}: { name, sku, barcode, quantity, isDeleted, updatedAt, ... }
  │       └── counts/{id}: { previousQty, countedQty, reason, countedAt }
```

## Monetization & Feature Gating

**Free tier** limits: 5 storages, 50 items/storage, last 30 days analytics, ad-supported.  
**Pro** (`isPro`): unlimited everything, full analytics, no ads.  
**Remove Ads** (`hasRemovedAds`): one-time purchase, keeps free-tier limits.

Product IDs:
- `com.vishuddhi.smartinventory.pro.monthly` — $2.99/month
- `com.vishuddhi.smartinventory.pro.annual` — $22.99/year
- `com.vishuddhi.smartinventory.removeads` — $3.99 one-time

All feature gates check `SubscriptionManager.shared.isPro` or `hasRemovedAds`.

## Ad Integration

`AdManager.shared.recordCompletion(event:)` must be called after every significant user action (item added, storage created, export completed, etc.) — this drives ad frequency logic (every 3 actions, min 5 min between ads). Ads are automatically suppressed for Pro/Remove Ads purchasers.

**Always use test ad unit IDs during development** — they're defined in `AdManager.swift` and toggled by the `isSimulator` / debug flag. Live ad unit IDs are in the same file.

## Key Setup Requirements

See `XCODE_SETUP_GUIDE.md` for full setup steps. Critical items:

- `GoogleService-Info.plist` must be in `AITest/` (excluded from git; each dev adds their own)
- `Info.plist` must include `GADApplicationIdentifier`, ATT usage description, camera usage description
- Crashlytics **Run Script** build phase must upload dSYMs (script references `firebase-ios-sdk` package path)
- In-App Purchase capability must be enabled in Xcode signing & capabilities

## Concurrency Patterns

- All managers are `@MainActor` — use `Task { @MainActor in ... }` when bridging
- Firestore writes use fire-and-forget `Task` — never `await` them in the UI path
- `@preconcurrency` imports used for non-Sendable Firebase/GoogleSignIn ObjC types
- `SendableAd<T>` wrapper in `AdManager` bridges non-Sendable ad objects across actor boundaries

## Important Files

- `AITest/AITestApp.swift` — app entry, `AppDelegate` (Firebase config, FCM, Google Sign-In redirect), SwiftData container, manager injection
- `AITest/Models/FirestoreManager.swift` — entire cloud sync strategy; read before modifying any sync behavior
- `AITest/Models/AdManager.swift` — ad lifecycle, completion events, frequency logic; read before adding new user actions
- `AITest/Models/SubscriptionManager.swift` — all StoreKit 2 purchase/entitlement logic
- `SmartInventory.storekit` — local StoreKit config for IAP testing
