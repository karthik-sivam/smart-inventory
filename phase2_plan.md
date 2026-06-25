# Phase 2 — Priority Split
*Based on app_review_report.md ratings + code review*

---

## 🔴 BLOCKER (Phase 2a)
*Active misinformation, data-integrity risk, or entirely dead features. Fix before any user touches the app.*

| # | Item | Why Blocker |
|---|---|---|
| B1 | Activity feed lost after sign-out — ActivityEvents not synced to Firestore | Dashboard's entire story section is permanently empty after first sign-out |
| B2 | Missing ActivityEvent calls in `saveEdits()` (qty change) and `markOutOfStock()` | Counts and zero-outs leave no trace in the feed at all |
| B3 | "Out of Stock ⊗" label + "Set to zero" shown on every item regardless of status | Actively tells users their in-stock item is out of stock — false alarm |
| B4 | Quick Count: "0" placeholder implies zero is the default + no large-change confirmation | A user who misreads the placeholder and saves will zero out their stock |
| B5 | Item detail opens as sheet from Storages tab, full-screen from Items tab | Same screen, completely different container — core navigation is broken |

---

## 🟠 CRITICAL (Phase 2b)
*Significant daily-use pain or missing core SMB functionality. Ship after blockers.*

| # | Item | Why Critical |
|---|---|---|
| C1 | Always-visible red trash + blue edit buttons on every row (B12) | Un-iOS, visually cluttered, constant accidental-delete risk |
| C2 | UOM shows "N/A" in Item Detail even when set (B8) | Wrong data shown to user |
| C3 | Storage chip truncates to "Kitchen (Te" in Items tab (B7) | Data is hidden/cut off |
| C4 | Barcode scanner not wired to Add/Edit Item form | SMBs type barcodes manually — unacceptable daily workflow |
| C5 | Smart decimal formatting — "5.0 units", "35.0 units" throughout (B10) | Unpolished, looks like a draft app |
| C6 | Reorder List — no way to act on low stock items | App tells you what's low but gives you nothing to do about it |

---

## 🟡 MAJOR (Phase 2c)
*High-value improvements. Elevates the product significantly but not show-stoppers.*

| # | Item | Why Major |
|---|---|---|
| M1 | Audit tab redesign — prioritised queue, last-audited timestamp per item | Gives the tab a distinct purpose from Items tab |
| M2 | Quick Count: +/- adjustment mode toggle | Professional inventory tools count deltas, not absolutes |
| M3 | In-app calculator on count screens — tap icon, calculate, paste result to quantity field | Eliminates app-switching mid-count; critical for box/batch quantity calculations |
| M4 | Item Detail content reorganisation — photo, category, recent activity for this item | Information hierarchy improvement |
| M5 | Maestro flow updates for all Phase 2 changes | Test coverage |
| M6 | New Maestro flows 28–32 (barcode, quick count safety, activity feed, reorder, swipe) | Test coverage |

---

*Blocker todolist is in todolist.rtf. Results tracked in automation_results.rtf.*
