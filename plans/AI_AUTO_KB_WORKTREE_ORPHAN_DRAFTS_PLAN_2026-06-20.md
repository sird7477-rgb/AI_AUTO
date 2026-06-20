# Plan — Un-orphan worktree-harvested knowledge drafts (#1, option A) 2026-06-20

Source: capture-coverage follow-up after the A2 auto-harvest shipped (origin/main
`02280b0`). Two-agent independent panel (problem verifier + approach critic) — all
claims ground-truth verified against current code.

## Problem (panel-verified)

The post-commit auto-harvest (`hooks/post-commit` → `knowledge-capture harvest --write`)
writes finding drafts into the **committing worktree's** `.omx/knowledge/drafts/`
(`knowledge-capture` `repo_root()` = `git rev-parse --show-toplevel`; `write_draft` →
`repo/.omx/knowledge/drafts`). But `obsidian-autopush.sh` collects only from
`HOME_ROOT` + the registry (`~/.local/state/ai-auto/projects.tsv`); it never enumerates
linked worktrees. So a Finding-trailered commit made in a linked worktree (the *designed
default* flow — `ai-tmux-worktree` gives each tmux window its own worktree + `.omx`)
produces a draft autopush will never see — an **orphaned draft**.

## Root cause / why it is worse than "just unpushed"

`.omx` is gitignored (`.git/info/exclude`), so the draft also never travels via git.
Decisive fact: `ai-tmux-worktree removability()` decides a worktree is removable from
`git status --porcelain`, which **ignores** gitignored `.omx`. So an orphaned draft does
NOT block removal; closing the tmux window runs `git worktree remove`, which **silently
and permanently deletes** the draft. The orphaning therefore *destroys* exactly the
high-value, just-distilled findings authored in worktrees. (Observed now: w6 has 7
orphaned drafts, w0 has 1 — none reachable by autopush.)

Why A2/A3 alone are insufficient (panel): an autopush-side "also scan `git worktree
list`" (A2) or a pre-push "sweep worktrees" (A3) only ever see **still-living** worktrees.
Because removal happens on window close and push is user-triggered later, the dominant
loss path (harvest → window closed → draft gone before next push) is unreachable by
A2/A3. They are complements, not the fix.

## Design (option A — write to a durable, non-worktree root at harvest time)

**A1-primary: harvest writes drafts to the PRIMARY (non-ephemeral) checkout's
`.omx/knowledge/drafts/`, resolved via the git common dir.**
- In `knowledge-capture`, resolve the drafts root as: parent of `git rev-parse
  --git-common-dir` (the primary worktree root — the pattern already proven in
  `ai-tmux-worktree primary_root_of`), then `<primary>/.omx/knowledge/drafts`. Fall back
  to the current `repo/.omx/...` when git-common-dir is unavailable (non-git / error).
- **CRITICAL resolver guard (plan-review #1, highest implementation risk):**
  `git rev-parse --git-common-dir` returns a **relative** path (`.git`) when run from the
  PRIMARY itself. Resolve it against the REPO path, not the process cwd: use
  `git -C <repo> rev-parse --git-common-dir` and `os.path.abspath(os.path.join(repo,
  common))`, then take its parent. (`<repo>` is `repo_root()` = `--show-toplevel`.) A naive
  port that resolves the relative `.git` against `os.getcwd()` silently yields the WRONG
  primary and re-orphans every draft while appearing to work. The shell precedent
  `primary_root_of` only gets this right because it `cd`s into the worktree first.
- The primary checkout (`/root/workspace/ai-lab`, the home repo) is **never
  auto-removed**, so drafts there are durable. It is already `HOME_ROOT` =
  `PROJECTS[0]` in autopush, so **collection needs ZERO change** and dedup
  (`existing_repeat_keys`, per-drafts-dir) now sees all worktrees' harvests in one dir.
- Net: drafts never live in an ephemeral worktree → the `removability` blind spot cannot
  destroy them; all worktrees feed the one canonical drafts dir the autopush already reads.

**Required: make `write_draft` concurrency-safe** (now that one dir receives writes from
multiple worktrees). Today it `os.replace`s a FIXED `path + ".tmp"` — two worktrees
harvesting the same finding the same day share the tmp path. Fix (plan-review #5, precise):
create the temp with `mkstemp` **in the destination drafts dir** (same filesystem, so
`os.replace` stays atomic), then atomic-replace onto the deterministic final filename.
Because the filename AND the full markdown are deterministic for a given finding+day, two
concurrent writers produce byte-identical content to the same path → last-writer-wins on
identical bytes = idempotent, no corruption, no duplicate. The `existing_repeat_keys` TOCTOU
is therefore harmless (both writers converge on the same file); **`flock` is NOT needed.**

**Migration = one-time manual sweep, NOT a standing A2 net** (plan-review #2). Rationale:
`knowledge-collect copy_note` namespaces the vault target by `project_namespace(repo) =
repo.name--sha256(repo)[:12]`, so a linked-worktree path and the primary path hash to
DIFFERENT `Projects/` folders, and there is no cross-drafts-dir dedup — a standing
"autopush also scans `git worktree list`" net would permanently double-push (two vault
notes, two `mark_pushed` write-backs) every finding that exists in both a worktree and the
primary. Instead, do a ONE-TIME sweep of the current live worktrees' orphans into the
primary `.omx/knowledge/drafts` during rollout (e.g. copy each live worktree's drafts in,
letting per-dir dedup collapse repeats), then rely solely on the harvest-time redirect.
Already-removed worktrees' orphans are unrecoverable (accept).

## Key decision (call out for plan review)

Drafts root = **primary-worktree `.omx`** (recommended v1) vs **`~/.local/state/ai-auto/
knowledge-drafts/`** (panel's "cleaner" alternative).
- Primary-worktree `.omx`: simplest — durable (home never removed), zero collection-side
  change (already `HOME_ROOT`), reuses existing dedup. Mild layering smell (a linked
  worktree writes into the primary's runtime dir), but the primary is the natural canonical
  home. **Recommend for v1.**
- `~/.local/state/ai-auto/knowledge-drafts/`: outside every worktree (no layering smell,
  most durable) BUT `knowledge-collect` hardcodes `repo/.omx/knowledge/drafts` and rejects
  non-git roots, so it needs a new `--drafts-dir` ingest path + an autopush change.
  More moving parts; defer unless review prefers it.

## Writer-isolation check

`docs/WORKFLOW.md` "Writer 격리" governs *tracked/working-tree* files (staging, review
state) to prevent edit/review races. `.omx/knowledge/drafts` is gitignored runtime state,
never staged. Writing harvested drafts cross-worktree into the primary `.omx` does not
violate the staging invariant; it is a scoped, documented exception. The only real cost is
the write-concurrency race, handled by the `write_draft` fix above.

## Risks / mitigations

- Concurrent same-finding harvest into the shared dir → unique tmp + idempotent overwrite
  (and optionally `flock` the drafts dir).
- `mark_pushed` writes back into the source draft → with a durable primary-`.omx` root the
  file no longer vanishes mid-push (an argument for the durable root).
- Migration: harvest-side change is forward-only; old orphans in already-removed worktrees
  are unrecoverable (accept). Live-worktree legacy orphans rescued by the A2 net.
- Reversibility: revert the resolver → drafts return to per-worktree `.omx`. Fully reversible.

## Verification

- verify-machinery: assert harvest from a *linked worktree* lands in the primary checkout's
  `.omx/knowledge/drafts` (fixture: create a linked worktree, commit a Finding-trailered
  commit, run the hook, assert the draft is in the primary not the linked worktree); assert
  concurrency-safe write (two harvests of the same finding → one idempotent draft, no
  corruption); assert the A2 net adds live worktrees to autopush `PROJECTS`.
- Each change = its own RALPH loop (plan→implement→`REVIEW_DECISION_GATE=1` unanimous→
  commit).
- **No template bump / mirror parity for the harvest fix** (plan-review #3): the change
  lives in `tools/knowledge-capture`, a SINGLE-SOURCE global PATH helper with NO
  `templates/automation-base/` mirror — `check-template-version` does not apply and no
  version bump is required UNLESS `templates/automation-base/hooks/post-commit` is also
  changed (it is not in this plan). Do not add a phantom parity/bump step.
- Live dogfood: a Finding commit in THIS linked worktree should now land in the home
  checkout's `.omx/knowledge/drafts`, where autopush (run from the primary) collects it.
- **Collection assumption (plan-review #4):** "zero collection change" holds only when
  `obsidian-autopush.sh` is run from the PRIMARY checkout (its `HOME_ROOT` = the script's
  own toplevel); running it from a linked worktree's copy would scope to that worktree.
  This matches the normal flow; note it, do not re-architect autopush.

## Out of scope / deferred

- `~/.local/state` shared-root variant (deferred unless review prefers it).
- Recovering already-lost orphans in removed worktrees (unrecoverable).
- The broader #2 version-management/distribution redesign (separate plan).

## Validation trail

- **AI council (validity):** 2-agent panel ground-truth-verified the orphan problem
  (CONFIRMED, worse than claimed — auto-removal of a clean worktree silently destroys the
  gitignored draft) and rejected A2/A3 as primary fixes; recommended harvest-time redirect
  to a durable root.
- **AI plan review:** verdict **GO-WITH-CHANGES**. Core design correct; durability of the
  primary `.omx` verified (nothing wipes `.omx/knowledge/drafts` — `archive-omx-artifacts.sh`
  touches only `review-results`). Required changes APPLIED to this plan: (1) the relative
  common-dir resolver guard (resolve against the repo path, not cwd); (2) A2 standing net →
  one-time manual sweep (avoid repo-hash-namespaced double-push); (3) drop the inapplicable
  parity/template-bump step (`knowledge-capture` is single-source `tools/`); (4) note the
  autopush-from-primary assumption; (5) precise `mkstemp`-in-dest-dir concurrency fix, no
  flock.
- **Status:** plan ready to implement as a RALPH loop on request. Highest-risk item: the
  resolver relative-path guard (#1).
