# Cursor Spec — master_scope_v1 Consolidation Merge

**Goal:** Merge all 10 shipped feature branches into a single staging branch `master_scope_v1_qa` so CEO can run one manual-QA pass against one build, then fast-forward `master_scope_v1` if QA is green.

**Base branch:** `master_scope_v1_qa` (NEW — created off `master_scope_v1`).
**Do NOT touch `master_scope_v1` directly.** It stays clean until QA passes.
**Estimate:** 5 story points. One Cursor session, ~45–90 min depending on conflict count.
**Owner:** stoqly-ios-engineer.

---

## Pre-flight (paste block 1)

```bash
cd ~/Documents/My\ Apps/SmartInventory/smart-inventory

# --- Preserve current uncommitted work ---
git status --short
# Expect:
#  M AITest/Localizable.xcstrings
# ?? docs/Stoqly_master_scope_v1_Manual_QA.xlsx
# ?? docs/cursor-spec-iOS-A4b.md
# ?? docs/handoff-2026-08-22.md
# ?? docs/cursor-spec-consolidation.md   (this file)

git stash push -u -m "pre-consolidation snapshot 2026-08-24" \
  AITest/Localizable.xcstrings \
  docs/handoff-2026-08-22.md \
  docs/cursor-spec-iOS-A4b.md \
  docs/cursor-spec-consolidation.md \
  docs/Stoqly_master_scope_v1_Manual_QA.xlsx

git stash list | head -3   # verify a new stash entry landed on top

# --- Sync and confirm all branches present ---
git fetch origin --prune
git branch -a | grep -E "iOS-|master_scope"

# --- Verify each branch head matches origin (no local-only work) ---
for b in iOS-A1 iOS-A2 iOS-A3 iOS-A4 iOS-A4b iOS-A5-pre iOS-A5 iOS-F1 iOS-F3 iOS-F4 iOS-F8; do
  local_sha=$(git rev-parse --short $b)
  remote_sha=$(git rev-parse --short origin/$b)
  [ "$local_sha" = "$remote_sha" ] && echo "$b: in sync ($local_sha)" \
    || echo "$b: DIVERGED local=$local_sha remote=$remote_sha  ← STOP and reconcile"
done
```

If any branch shows DIVERGED, stop and reconcile with the CEO before proceeding.

---

## Create staging branch (paste block 2)

```bash
# Start from master_scope_v1 tip
git checkout master_scope_v1
git pull --ff-only origin master_scope_v1

# Create fresh staging branch (delete + recreate if it already exists)
git branch -D master_scope_v1_qa 2>/dev/null || true
git checkout -b master_scope_v1_qa

# Confirm you're on the staging branch at master_scope_v1's tip
git log --oneline -1
# Expect: 0a2c5ec Merge pull request #3 ...
```

---

## Merge order

Merge in THIS EXACT ORDER (handoff §5, with F7 removed since it was folded into A4b):

1. `iOS-F3`
2. `iOS-F4`
3. `iOS-F1`
4. `iOS-A2`
5. `iOS-A1`
6. `iOS-A3`
7. `iOS-A4`
8. `iOS-A4b`
9. `iOS-A5-pre`
10. `iOS-A5`
11. `iOS-F8`

Why this order: (a) F-branches first because they're independent bug fixes with tight scope, (b) A1 near the top because it's near-no-op (per its automation_results.rtf entry: `isPro was already StoreKit-derived on origin/main`), (c) A4 before A4b because A4b is stacked on A4, (d) A5-pre before A5 because A5 depends on the confidence field A5-pre added, (e) F8 last because it's a UI addition unlikely to interact with earlier merges.

---

## Merge command per branch (paste block 3 — repeat for each)

For each branch B in the order above:

```bash
git merge --no-ff --no-edit origin/$B -m "consolidate: merge $B into master_scope_v1_qa"

# If merge succeeds cleanly, move to next branch.
# If merge FAILS with conflicts, follow the "Conflict resolution" section below.
```

Use `--no-ff` so each merge shows as its own commit — makes bisecting easier if QA later fails.

**Suggested driver script** (paste as one block, but review each merge output before proceeding to the next):

```bash
ORDER=(iOS-F3 iOS-F4 iOS-F1 iOS-A2 iOS-A1 iOS-A3 iOS-A4 iOS-A4b iOS-A5-pre iOS-A5 iOS-F8)
for B in "${ORDER[@]}"; do
  echo ""
  echo "═══════════════════════════════════════════════"
  echo "  Merging $B"
  echo "═══════════════════════════════════════════════"
  git merge --no-ff --no-edit "origin/$B" -m "consolidate: merge $B into master_scope_v1_qa"
  status=$?
  if [ $status -ne 0 ]; then
    echo ""
    echo "❌ CONFLICT on $B — STOP HERE. Resolve per the Conflict Resolution section, then:"
    echo "   git add -A && git commit --no-edit"
    echo "   Then rerun this loop from the branch AFTER $B."
    break
  fi
  echo "✅ $B merged cleanly."
done
```

---

## Conflict resolution — the two files you WILL see conflicts on

### `automation_results.rtf`

Every branch appended a completion entry to this shared RTF at the tail. Every merge after the first will conflict on the last ~10–15 lines.

**Resolution rule:** keep BOTH sides' new entries, in this order — the entry that was already on `master_scope_v1_qa` first (`<<<<<<< HEAD` block), then the entry from the incoming branch (`>>>>>>> origin/…` block). Delete the conflict markers. Never delete a branch's completion entry.

Recipe:
```bash
# When you see:
# <<<<<<< HEAD
#   {\b iOS-F3: ...}\par [COMPLETED]\par
#   \bullet ...\par
#   \par
# =======
#   {\b iOS-F4: ...}\par [COMPLETED]\par
#   \bullet ...\par
#   \par
# >>>>>>> origin/iOS-F4

# Edit to:
#   {\b iOS-F3: ...}\par [COMPLETED]\par
#   \bullet ...\par
#   \par
#   {\b iOS-F4: ...}\par [COMPLETED]\par
#   \bullet ...\par
#   \par
```

The final `}` closing brace at the end of the RTF must remain the LAST character in the file — everything else goes above it.

### `maestro/run_all.yaml`

Multiple branches add lines. Order in the file is: existing → then A4 added flow 81 → then A4b added flow 82. If two branches both add lines in the same region, keep both, preserving A4's line first, then A4b's.

Watch out for the pre-existing collision: `81_add_item_progressive_disclosure.yaml` and `81_smart_count_open.yaml` both use "81_". The Smart Count section (`# ── Smart Count flows (81–87) ─────────────────────`) stays where it is. A4's line goes into the Bulk Import / general section above it. This was correct on iOS-A4 already — just preserve both.

### `AITest/Services/AnalyticsManager.swift`

Likely conflict: three branches added new `StoqlyEvent` enum cases and their dispatch:
- F1: `trial_started`, `trial_converted`, `trial_cancelled`, `trial_expired`
- F4: `ad_requested`, `ad_loaded`, `ad_failed`, `ad_impression`, `ad_clicked`, `ad_dismissed`
- A4b: `add_item_more_details_toggled`

If the enum block conflicts, keep all cases from all branches. If the switch statement in `AnalyticsManager.track` conflicts, keep all case arms from all branches. Order within the enum: preserve each branch's grouping.

### `CLAUDE.md`

Multiple branches may have touched this to remove stale pre-ship blocker text (A1 did). Keep the removal (both branches want it gone), even if the surrounding text differs.

### Any other conflict

STOP. Do not guess. Post the conflict text back to Claude/Cowork with the file path and the surrounding 20 lines. Get direction before resolving.

---

## After all 10 merges land — verification (paste block 4)

```bash
# Log check: expect 10 merge commits + master_scope_v1's tip
git log --oneline master_scope_v1..master_scope_v1_qa | head -25

# Working tree must be clean
git status --short   # expect empty

# Build verify (this is the real merge gate before push)
xcodebuild -project AITest.xcodeproj \
  -scheme SmartInventory \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build 2>&1 | tail -30
# Expect: BUILD SUCCEEDED, exit 0
# Any error: STOP. Report the error, revert the last merge (git reset --hard HEAD~1), do not push.
```

---

## Restore uncommitted work (paste block 5)

Only after build succeeds:

```bash
git stash pop
# Expect: your Localizable.xcstrings modification and the four docs come back.

# Commit the docs to the staging branch (they belong in the audit trail)
git add docs/handoff-2026-08-22.md \
        docs/cursor-spec-iOS-A4b.md \
        docs/cursor-spec-consolidation.md \
        docs/Stoqly_master_scope_v1_Manual_QA.xlsx
git commit -m "docs: consolidation audit trail — handoff, A4b spec, consolidation spec, QA checklist"

# The Localizable.xcstrings edit is left uncommitted for CEO to decide on separately.
```

---

## Update automation_results.rtf with the consolidation entry (paste block 6)

Since RTF editing via Cursor is fiddly, this is one final edit before push.

Append at the END of `automation_results.rtf`, INSIDE the final `}`:

```
\par
{\b CONSOLIDATION: master_scope_v1_qa}\par
[COMPLETED]\par
\bullet Merged 10 branches into master_scope_v1_qa in order: F3, F4, F1, A2, A1, A3, A4, A4b, A5-pre, A5, F8.\par
\bullet Conflicts resolved: automation_results.rtf (kept all entries), maestro/run_all.yaml (preserved both sections), AnalyticsManager.swift (kept all events).\par
\bullet Build: xcodebuild SmartInventory iPhone 17 Pro simulator \emdash  exit 0, BUILD SUCCEEDED.\par
\bullet Ready for CEO manual QA per docs/Stoqly_master_scope_v1_Manual_QA.xlsx. master_scope_v1 UNCHANGED; fast-forward pending QA.\par
```

Then:
```bash
git add automation_results.rtf
git commit -m "consolidate: master_scope_v1_qa completion entry"
```

---

## Push + PR (paste block 7)

```bash
git push -u origin master_scope_v1_qa

# Open PR against master_scope_v1 with:
#   Title: "Consolidation: master_scope_v1_qa (Wave 1 + Wave 1.5)"
#   Body:  See PR body template below.
```

**PR body template:**
```
## Summary
Consolidates all 10 Wave 1 + Wave 1.5 story branches into staging branch `master_scope_v1_qa` for CEO manual QA. Do NOT merge this PR — it's for QA review only. On QA green, fast-forward master_scope_v1 to this tip via `git push origin master_scope_v1_qa:master_scope_v1`.

## Branches merged (in order)
1. iOS-F3 — Photo paywall via .fullScreenCover
2. iOS-F4 — AdMob Amplitude instrumentation
3. iOS-F1 — Real 7-day free trial
4. iOS-A2 — Barcode debug prints
5. iOS-A1 — isPro revert
6. iOS-A3 — Splash + Auth dark-mode
7. iOS-A4 — Add-item progressive disclosure
8. iOS-A4b — Progressive-disclosure polish
9. iOS-A5-pre — SmartSales confidence
10. iOS-A5 — SmartCount/SmartSales review UX
11. iOS-F8 — Entry chips on manual screens

## Build
xcodebuild iPhone 17 Pro simulator — BUILD SUCCEEDED.

## Test plan
CEO runs `docs/Stoqly_master_scope_v1_Manual_QA.xlsx` against this branch.
74 test cases + 10-case smoke + release-gate checklist.
```

---

## Definition of Done

1. `master_scope_v1_qa` exists on origin with 10 merge commits + docs commit + consolidation-entry commit.
2. `master_scope_v1` is UNCHANGED (still at `0a2c5ec`).
3. Build passes on the staging branch.
4. Working tree is clean at end (except the intentionally-preserved Localizable.xcstrings edit).
5. PR opened against master_scope_v1, marked "for QA review — do not merge".
6. automation_results.rtf has the consolidation entry.
7. Slack/message to CEO: "master_scope_v1_qa is ready — run the QA checklist. Do not merge the PR until QA is green."

---

## Fast-forward instructions (for later, AFTER QA is green)

**Only run this after every P0 in the QA sheet is Pass and the SMK regression smoke is Pass.**

```bash
# Fast-forward master_scope_v1 to the staging branch tip
git checkout master_scope_v1
git merge --ff-only master_scope_v1_qa
git push origin master_scope_v1

# Optional: keep master_scope_v1_qa around as a snapshot, or delete it
git push origin --delete master_scope_v1_qa   # only if you don't want the record
git branch -d master_scope_v1_qa
```

---

## Out of scope (do NOT do)

- Do NOT merge `master_scope_v1_qa` into `master_scope_v1` yet — that happens only after QA.
- Do NOT push to `master_scope_v1` directly.
- Do NOT run `maestro test maestro/run_all.yaml` — DEFERRED per CEO.
- Do NOT skip a conflict by taking one side arbitrarily. If unsure, stop and ask.
- Do NOT alter any of the 10 story branches themselves — they must stay as source of truth.

---

## Beyond the ask

- **Risk — RTF file corruption:** RTF is finicky. If your editor eats the final `}` or reflows escape sequences (`\emdash`, `\par`), the file will render broken. Always diff visually after resolving RTF conflicts. Use `plain text editor mode` in Cursor, not rich-text.
- **Risk — Localizable.xcstrings uncommitted:** the CEO's in-progress edit (`Preview feedback prompt` key) is preserved via stash. On the staging branch, `git stash pop` restores it. If pop conflicts (unlikely — none of the 10 branches touch `Localizable.xcstrings` in that region), leave it stashed and hand back to CEO.
- **Fallback if a merge is unrecoverable:** `git merge --abort` returns to a clean state. Report which branch failed, why, and stop. Don't force-resolve — the CEO decides whether to fix on the source branch or exclude it from this consolidation.
- **A5 depends on A5-pre.** If somehow A5 merges first (order accident), the SmartSales confidence rendering will hit missing fields and fail to compile. The order above is deliberate.
