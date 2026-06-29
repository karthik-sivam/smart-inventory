# Org-Skill Findings for Stoqly

> These are observations noted during Stoqly Phase 7 planning. Org skills are NOT modified — these are findings only, for the CEO's awareness. If changes to org skills are ever desired, raise them in Settings → Capabilities (skill editor).

Last updated: 2026-06-27

---

## Finding 1: §7 Project Context References "Match Podu" by Name

**Skill:** `vishuddhi-beta:org-operating-manual`, Section §7 "Loading project context"

**Issue:** The org manual hardcodes project-specific document paths for "Match Podu":
- `Match-Podu-Plan.md`
- `Match-Podu-Market-Research.md`
- `Match-Podu-Org-Roles.md`

**Impact for Stoqly:** When role skills (PM, Designer, Engineers, QA) read the org manual to understand where to load project context, they encounter Match Podu paths that don't exist in the Stoqly workspace. They need to be explicitly told to use Stoqly's project docs instead.

**Workaround in use:** Every agent prompt for Stoqly explicitly instructs skills to read:
- `/mnt/.claude/skills/stoqly-project/references/architecture.md`
- `/mnt/.claude/skills/stoqly-project/references/conventions.md`
- `/mnt/.claude/skills/stoqly-project/references/phase-status.md`

**Suggested fix (for org skill owner to implement):** Generalise §7 to say "load the project's plan documents — the exact paths depend on the project you're working on; the CEO or Scrum Master will specify them at task time."

---

## Finding 2: Org Manual Doesn't Know Stoqly's Critical Coding Rules

**Skill:** `vishuddhi-beta:org-operating-manual`

**Issue:** The iOS/Backend engineer skills inherit the org manual's general coding standards but have no awareness of Stoqly-specific non-negotiable patterns:
- `modelContext.safeSave(context:)` — never `try? modelContext.save()`
- `ActivityEvent` must be inserted BEFORE `modelContext.delete()`
- Barcode scanner uses `.fullScreenCover`, never `.sheet`
- `smartFormatted` for quantities, `%.2f` for currency only
- `ItemDetailView` must not have inner `NavigationStack`

**Impact:** Engineer skills writing or reviewing code for Stoqly could inadvertently violate these rules, causing silent data loss or runtime crashes.

**Workaround in use:** Every engineer agent prompt for Stoqly explicitly references `conventions.md` and lists the critical rules as MUST-follow constraints.

**Suggested fix:** Either (a) the Scrum Master injects conventions at sprint start as a "project rules" block, or (b) the engineer skills have a "read project conventions before any code" step that is project-agnostic.

---

## Finding 3: Org Skills Are Tuned for a Two-Platform (Android + iOS) Org

**Skill:** `vishuddhi-beta:org-operating-manual`, §2 Roles table

**Issue:** The org structure includes a dedicated Android Engineer skill, implying a two-platform org (Android + iOS). Stoqly is iOS-only.

**Impact:** Scrum Master and PM skills may occasionally reference Android deliverables in their plans. These must be ignored or called out.

**Workaround in use:** All Stoqly agent prompts specify "iOS only — no Android deliverables needed."

---

## Finding 4: Org Manual DoD Includes "Works on Low-End Android Profile"

**Skill:** `vishuddhi-beta:org-operating-manual`, §5 Definition of Done

**Issue:** Item 5 of the DoD includes: "works on a low-end Android profile and offline where relevant."

**Impact:** For Stoqly (iOS-only), this criterion is irrelevant and could cause confusion when QA checks the DoD.

**Workaround in use:** QA agent prompts for Stoqly replace this with "works on iPhone SE (smallest supported screen, iOS 16 minimum) and offline where relevant."

---

## Summary Table

| # | Finding | Severity | Workaround |
|---|---------|----------|------------|
| 1 | §7 project docs hardcoded to Match Podu | Medium | Explicit paths in every agent prompt |
| 2 | Stoqly coding rules not in org manual | High | Conventions.md referenced in every engineer prompt |
| 3 | Two-platform org, Stoqly is iOS-only | Low | "iOS only" stated in every agent prompt |
| 4 | DoD references Android | Low | QA prompt replaces with iPhone SE + iOS 16 |
