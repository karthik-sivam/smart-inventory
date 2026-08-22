# Stoqly — Phase Roadmap & Status

**⚠️ SOURCE OF TRUTH: `automation_results.rtf`**
This file reflects actual shipped state as of the last update. If anything looks
uncertain, read `automation_results.rtf` first — it's the authoritative log of
every Cursor run and Maestro result. Never trust this file alone for "is X done?"

Last updated: 2026-06-18

---

## Phase 1 — Core MVP ✅ COMPLETE

All core inventory management features shipped:
- Storage areas (create, edit, delete, color-coded)
- Items (add, edit, delete, barcode scan, photo upload)
- Quick count + full count workflow
- Dashboard KPIs (total storages, items, low stock count, total value)
- Basic analytics (30-day history on free)
- CSV + PDF export
- Firebase Auth + Firestore sync
- Push notifications (low stock alerts)
- Paywall (Pro + Remove Ads)
- Pre-auth onboarding (4-page walkthrough)
- Maestro UI test suite (flows 01–20)

---

## Phase 2 — Inventory Intelligence ✅ COMPLETE

| Feature | Status |
|---------|--------|
| QuickCountView — Set to / Adjust by toggle, disabled save, large-change alert | ✅ Done |
| ItemDetailView — NavigationStack removed from body; sheet callers wrap it | ✅ Done |
| ItemFormViewModel — `smartFormatted` for qty fields | ✅ Done |
| Activity Feed — 20 events on Dashboard, "See All" sheet | ✅ Done |
| ReorderListView — deficit-sorted, Out of Stock / Low Stock badges | ✅ Done |
| ItemDetailView — AsyncImage photo + per-item Recent Activity | ✅ Done |
| CountViewModel — `.due` / `.uncounted` / `.lowStock` / `.all` filter chips | ✅ Done |
| Phase 2 Maestro — bundle ID → `com.vishuddhi.stoqly`, branding → "Stoqly" | ✅ Done (with minor known issues) |

---

## Phase 3 — Polish & Retention ✅ COMPLETE

All Phase 3 sub-items are shipped. See `automation_results.rtf` for per-item details.

| Sub-phase | Feature | Status |
|-----------|---------|--------|
| 3.1 | Dark Mode Audit — SplashScreenView + AuthView semantic colours | ✅ COMPLETED 2026-05-13 |
| 3.2 | Post-Login Onboarding — `PostLoginOnboardingView`, `hasSeenPostLoginOnboarding` flag | ✅ COMPLETED 2026-05-13 |
| 3.3 | Empty States — `ContentUnavailableView` in all major list views | ✅ COMPLETE |
| 3.4 | Dashboard Improvements — delta badges on KPI cards, `InventoryHealthCard`, stock attention banner | ✅ COMPLETED |
| 3.5 | Form Polish — keyboard toolbar, inline validation, disabled save | ✅ COMPLETE |
| 3.6 | Batch Expiry Tracking — `InventoryBatch` model, FIFO display, QuickCount "Track as new batch" | ✅ COMPLETED 2026-05-13 |
| 3.7 | Deletion Confirmation Toast — `ToastView` wired in ItemListView, StorageDetailView, StorageListView | ✅ COMPLETED |
| 3.8a | Search & Spotlight — search history chips, `SpotlightManager`, deep-link handler | ✅ COMPLETED |
| 3.8b | Monetisation Polish — storage cap indicator, contextual paywall, trial expiry banner | ✅ COMPLETED |
| 3.9 | Performance & Sync — write debounce (1.5s), background flush, foreground pull throttle (15min), concurrent Firestore writes (`withTaskGroup`), search debounce (250ms) | ✅ COMPLETED |
| 3.10 | Phase 3 Maestro — flows 34–36, branding sweep | ✅ COMPLETED WITH ISSUES (known flow failures are pre-existing, spec items pass) |

---

## Phase 4 — Collaboration & Scale ✅ COMPLETE

All Phase 4 parts shipped. See `automation_results.rtf` for per-section details.

| Part | Feature | Status |
|------|---------|--------|
| 4 Part 1 | `performedBy` on all ActivityEvents, `TeamMember` model, `TeamManager` singleton, workspace switching, invite send/accept/decline, `TeamMembersView` | ✅ COMPLETED |
| 4 Part 2 | Role gates (`canEdit`, `canDeleteItem`, `canDeleteStorage`), viewer read-only banner, workspace indicator, `ItemTemplate` model + Firestore sync, `TemplatePickerView`, "Save as Template" | ✅ COMPLETED |
| 4 Part 3 | Templates Maestro flows 63–71 | ✅ COMPLETED WITH ISSUES |

---

## Bulk Import ✅ COMPLETE (2026-06-17)

- BulkImportView — CSV + XLSX support, column-mapping UI, preview, progress, error rows
- `ImportField` enum (11 cases: name, quantity, unitCost, category, sku, barcode, minQty, maxQty, storageName, notes, skip)
- `AddStorageView` — `onStorageAdded` callback for post-import storage creation
- `ActivityEvent.BulkImportCompleted` event type
- Maestro flows 78–80 (bulk import tests) — PASS 2026-06-18

---

## M5 — Import & Reorder Improvements ✅ COMPLETE (2026-06-18)

| Item | Detail |
|------|--------|
| UOM import | `ImportField.uom` case, auto-detect column headers, lookup-or-create UOM in performImport |
| Supplier email | `supplierEmail: String` on `Storage` model + Firestore sync |
| EditStorageView | Supplier email TextField |
| ReorderListView | "Email Supplier" button → pre-drafted `mailto:` link |

---

## M6 — SMB Review Gaps ⏳ PENDING (Cursor)

Written in `todolist.rtf` on 2026-06-18. Not yet run.

| Item | Detail |
|------|--------|
| UOM import | `ImportField.uom` case, auto-detect column headers, lookup-or-create UOM in performImport |
| Supplier email | `supplierEmail: String` on `Storage` model + Firestore sync |
| EditStorageView | Supplier email TextField |
| ReorderListView | "Email Supplier" button → pre-drafted `mailto:` link |

---

## M6 — SMB Review Gaps ⏳ PENDING (Cursor)

Written in `todolist.rtf` on 2026-06-18. Not yet run.

| Item | Detail |
|------|--------|
| Multi-storage reorder email | Group reorder items by storage, show one "Email [Storage] Supplier" button per storage with a supplierEmail set |
| Per-item % threshold | Add `reorderPercentage: Double` to InventoryItem; `isLowStock` uses % of maxQty when set; EditItemView toggle |
| Offline write queue | FirestoreManager queues failed writes to UserDefaults; flushes on foreground reconnect |
| Daily summary notification | `scheduleDailySummary(hour:minute:)` in NotificationManager; Settings toggle + time picker |
| Cost layer foundation | `lastPurchasePrice` + `lastPurchasedAt` on InventoryItem; cost variance label in ItemDetailView; price-creep banner on Dashboard |

---

## QuickCountView First-Time Tips ✅ DONE (2026-06-18, direct edit)

Added directly to `StorageDetailView.swift`:
- `@AppStorage("stoqly_hasSeenCountTips")` flag
- Sheet shows on first open, 3 tip cards: FIFO batch tracking, par levels, adjust-by mode
- "Got it" dismisses and sets flag permanently

---

## Maestro Suite — Latest Run

| Run | Date | Result |
|-----|------|--------|
| Full suite (75 flows, simulator) | 2026-06-18 | PASS 45/75 — known failures are pre-existing YAML issues, not regressions |
| M4 isolated (flows 78–80, bulk import) | 2026-06-18 | PASS 3/3 |

---

## Phase 5 — Data Foundation 📋 Post-launch

- 5.1 Vendor model (Vendor, VendorPrice, preferredVendor on items, price comparison)
- 5.2 Excel/CSV import with AI column mapping (Claude API → user confirms → bulk insert)
- 5.3 Manual sales entry (SaleEvent model, velocity calculation, sales analytics)

---

## Phase 6 — Intelligence 📋 Post-launch

- 6.1 AI reorder predictions ("runs out in ~N days", push notification)
- 6.2 Vendor price intelligence (cheapest supplier alerts, price trend)
- 6.3 Invoice scan OCR (photo → Claude multimodal → structured rows → bulk insert)
- 6.4 AI insights dashboard (margin, slow-movers, anomaly detection)

---

## Phase 7 — Pro+ Tier & Live AI Camera 📋 Future

- 7.1 **Live AI Camera (SmartCount Pro+)** — AVFoundation live camera feed, samples 1 frame every 2s, sends each to Claude Vision, aggregates and deduplicates items across frames as the user pans the shelf. Solves the hidden-items problem that single-photo can't handle. Running count overlay updates progressively on screen. Tap Done → review → save. Estimated cost: ~15 Claude Haiku calls per session (≈ ₹5–10). Gated behind a Pro+ tier.
- 7.2 **Pro+ tier** — Pricing ladder: Free → Pro → Pro+. Pro+ includes: Live AI Camera (unlimited sessions), deeper analytics history (all-time), priority support. Gives a natural upsell path for larger SMBs (warehouses, multi-location retail).
- 7.3 Multi-location / franchise support — one owner account, multiple branch workspaces.

> 💡 Live AI Camera idea originated from a LinkedIn comment on the Stoqly launch post (July 2026): commenter pointed out that shelves have hidden items that a single photo can't count. Video/multi-frame scanning is the right answer — captures multiple angles as user walks, accumulates a full count.

---

## Critical Pre-Ship Checklist

Before any App Store submission:

- [ ] **Revert `SubscriptionManager.isPro` to `false`** (currently `true` for testing)
- [x] **Remove debug prints** in `BarcodeEnrichmentService.swift` (`print("[Enrichment]...")`) — none remain (iOS-A2)
- [ ] Run full Maestro suite — all flows pass (or known failures documented)
- [ ] Manual test on physical device (not just simulator)
- [ ] Verify Firestore security rules are production-ready
- [ ] Test StoreKit sandbox purchase + restore
- [ ] Review App Store screenshots match current UI (Stoqly branding, not Smart Inventory)
- [ ] Privacy policy and terms of service URLs live
- [ ] App Store Connect: products configured (`com.vishuddhi.stoqly.pro.monthly`, `.pro.annual`, `.removeads`)

---

## Cursor Delegation

Active spec in `todolist.rtf`:
- **M5**: Import & Reorder Improvements (UOM import, supplier email, mailto reorder)

After each Cursor run, **always read `automation_results.rtf`** before updating this file
or making any plan. `automation_results.rtf` is the ground truth — this file is a summary.
