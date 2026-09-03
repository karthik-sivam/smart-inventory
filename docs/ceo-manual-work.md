# CEO manual work (App Store Connect + consoles)

Cursor cannot do these. Nothing here is a code PR.

Last updated: 2026-09-01 (iOS-F2 **merged** as PR #23, `8507b77` on `master_scope_v1`).

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

## Amplitude tracking plan (project 832993) — DONE 2026-09-02, no longer on you

Officialized directly through the Amplitude MCP on branch `main` (main is unprotected, single environment, so no branch/merge was needed). All seven events are now in the plan, `isOfficial`, categorised, and documented with their properties:

| Category | Event | Was |
|---|---|---|
| Barcode bulk scan | `barcode_bulk_scan_started` | unexpected → in plan |
| Barcode bulk scan | `barcode_bulk_scan_abandoned` | unexpected → in plan |
| Barcode bulk scan | `barcode_bulk_scan_completed` | never ingested → pre-declared |
| Business profile | `business_profile_prompt_shown` | unexpected → in plan |
| Business profile | `business_profile_completed` | unexpected → in plan |
| Business profile | `business_profile_save_failed` | unexpected → in plan |
| Business profile | `business_profile_updated` | never ingested → pre-declared |

Standing rules captured in the event descriptions themselves, so they survive this doc:

- Do **not** fire per-beep `barcode_scan_result` from bulk sessions (keeps the single-scan funnel clean). Barcodes are commercial IDs, not PII; they are stored on items, not on these session events.
- `business_profile_prompt_shown` fires once per app session while the profile is missing, so a force-quit re-fires it. **Count uniques, not event totals** — or use a Funnel chart, which is user-based by construction.
- `business_city` is self-declared and deliberately named to avoid Amplitude's IP-derived `city` / `region`. Phone number, business name, and custom "Other" text are never sent.

### Note on the empty bulk-scan funnel — nothing to action yet

`barcode_bulk_scan_completed` has never fired. This is **expected**, not a finding: F2 (`8507b77`) is on `master_scope_v1` only — not merged to `main`, not tagged, and production is still 1.4 — so no real user has ever had the feature. The lone `_started` / `_abandoned` pair on 2026-09-01 (01:49 and 01:50, first_seen == last_seen on both) is a single local test session on merge night.

Read the funnel only after F2 ships in a released build. At that point the number that matters is `_completed ÷ _started` as **uniques**, segmented by `stage` on `_abandoned` — a high `scanned_count` with `stage=camera` would be the expensive failure (user did the work, lost it).

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
