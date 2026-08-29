# Feature spec — iOS-F2: Bulk barcode scan

**Track:** Wave 1.5 / paywall promise.
**Branch:** `iOS-F2` off `master_scope_v1`.
**Owner:** stoqly-ios-engineer. Decisions: CEO + Growth option A (2026-08-29).
**Estimate:** 5 sp.

---

## 1. Problem

The paywall sold “Barcode scanner pro **(bulk, history)**.” The app only did **one code → dismiss**. `canUseBarcodeScannerPro` was unused. That is a false Pro claim and blocks honest pricing tests.

## 2. Job to be done

Walk a shelf / receiving pile and capture ~20 barcodes **without reopening the camera**, then confirm and save into **one storage**.

## 3. Scope — IN (v1)

- Keep the camera open. Beep/haptic per accepted code. Queue in session.
- Bottom counter: how many **rows** (distinct codes) are queued.
- **Done** → review list → **Save all**.
- Same code again (after cooldown): increment that row’s qty.
- Match **barcode in the current storage**: existing item → qty += delta; else new item (name editable; enrichment may fill name/category).
- Free: **unlimited single scan** (unchanged Scan to Find / Add Item scanner).
- Pro: unlimited bulk sessions.
- Paywall row: drop “history”. Honest bulk copy + note “Free: single scan”.
- Entry: **Storage detail** toolbar (needs a storage).
- Scanner stays `.fullScreenCover`. Simulator uses manual-code entry into the same queue.

## 4. Scope — OUT (deferred)

- **F2b:** live overlay of item names on the finder; still-photo multi-barcode in one shot.
- **Phase 7:** Live AI Camera (shelf product identity, not barcodes).
- Durable **scan log** / receiving history screen (do not put “history” on the paywall until this exists).
- Monthly cap on Free single-scan (Growth option A: no cap).
- Matching barcodes across **other** storages (this session is storage-scoped).
- Coordinators, nested NavigationStack in modal add-item, `isPro = true` hardcode.

## 5. User stories

**Pro bulk**
- Given Pro and a storage, when I tap Bulk scan, then the camera stays open and a counter updates as I scan.
- Given a queued session, when I tap Done, then I see each code as New vs +N on {name}, can edit qty/name, uncheck rows, Save.
- Given Save, then existing items increment, new items insert, ActivityEvents + Firestore sync run, scanner dismisses.

**Free**
- Given Free, when I tap Bulk scan, then Paywall (`source=barcode_bulk`). Single-scan paths still work with no monthly N.

## 6. Success metrics

- Primary: Pro conversion from `paywall_shown` where `source=barcode_bulk`.
- Guardrail: single-scan `barcode_scan_result` volume should not collapse (bulk must not emit per-beep `barcode_scan_result`).
- Events: `barcode_bulk_scan_started` / `completed` / `abandoned`.

## 7. Analytics (no PII; barcodes not on session events)

| Event | Properties |
|---|---|
| `barcode_bulk_scan_started` | `source` (`storage_detail`) |
| `barcode_bulk_scan_completed` | `scanned_count`, `new_count`, `updated_count`, `duration_ms` |
| `barcode_bulk_scan_abandoned` | `stage` (`camera` \| `review` \| `empty`), `scanned_count`, `duration_ms` |

## 8. Risks

- Same code held in the viewfinder would spam qty → **1.2s per-code cooldown**.
- SwiftUI dropping a sheet after fullScreenCover → **review lives inside the same cover** (step: camera → review).
- Free item cap: bulk is Pro-only; still skip new inserts if cap hit.
