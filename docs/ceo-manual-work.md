# CEO manual work (App Store Connect + consoles)

Cursor cannot do these. Nothing here is a code PR.

Last updated: 2026-08-29 (iOS-F2 decisions locked: Growth option A).

---

## Trust-debt — App Store Connect listing

**Where:** App Store Connect → Stoqly → iOS version → Description (and subtitle / promotional text if the same phrases appear). English first, then any localized listings.

Source of claims: Release Gate tab in `docs/Stoqly_master_scope_v1_Manual_QA.xlsx`.

| ID | Claim to find and fix | What is true in the app | Suggested rewrite |
|---|---|---|---|
| **T1** | Listing says unlimited free items | Free = **5 storages × 50 items**. Pro = unlimited. | “Free: 5 storages and 50 items per storage. Unlimited items on Pro.” |
| **T2 (listing side)** | Listing implies cloud sync is Pro | Cloud sync is **free**. In-app onboarding was fixed in [PR #15](https://github.com/karthik-sivam/smart-inventory/pull/15). | Remove any “Pro cloud sync” line. Sync is included on Free. |
| **T3** | Listing overstates “AI reorder suggestions” | Reorder is **rules**, not AI: min qty or % of max, low-stock list, optional supplier email. “Runs out in ~N days” is still roadmap Phase 6. | “Low-stock alerts and a reorder list” — do not say AI reorder until that ships. |
| **T4** | “No manual entry, no errors” | Manual count and manual sale are **free**. AI flows always have a **review** step. | Delete that line. Optional: “AI drafts a list — you confirm before save.” |

**T5 / T6** were in-app/docs and are already merged (PRs #21 / #22). Do not re-do those in ASC unless the listing still quotes $2.99 / $22.99.

---

## After iOS-F2 merges (Amplitude)

Claude / data-analyst: officialize on project **832993** (create unexpected, then update metadata):

- `barcode_bulk_scan_started`
- `barcode_bulk_scan_completed` (`scanned_count`, `new_count`, `updated_count`, `duration_ms`)
- `barcode_bulk_scan_abandoned` (`stage`, `scanned_count`, `duration_ms`)

Do **not** fire per-beep `barcode_scan_result` from bulk sessions (keeps the single-scan funnel clean). Barcodes are commercial IDs, not PII; they are stored on items, not on these session events.

---

## Not this release (product, later)

| Item | Notes |
|---|---|
| **F2b** | Name/qty chips overlaid on the live camera; still-photo “detect every barcode in one shot.” |
| **Phase 7 Live AI Camera** | Multi-frame shelf **product** count (not barcodes). Separate from F2. |

---

## Other consoles still on you

- Manual QA of `master_scope_v1` per the xlsx (post-ship regression).
- F1 sandbox tester if the 7-day trial has not been verified on device.
- Native reviewer pass on T2’s 14 language drafts (`needs_review` in `Localizable.xcstrings`).
