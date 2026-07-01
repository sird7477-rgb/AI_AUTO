# Defense R13 — HOLISTIC/INTEGRATION + SUITE-INTEGRITY (RED TEAM)

Target: feat/global-toolize @ 26d96db. Read-only; all repros in mktemp temp repos. Worktree .git/config untouched.

## Suite integrity (all GREEN, non-flaky)
- `bash scripts/verify-machinery.sh` x2 → exit 0, exit 0.
- `( . hooks/git-scrub.sh && bash scripts/verify-machinery.sh )` x2 → exit 0, exit 0.
- `.venv/bin/python -m pytest -q` x2 → 237 passed, 1 skipped, exit 0 (both). `1 skipped` = documented todo-report quarantine (tests/test_todo_report.py:112, BASELINE.md 6e90184).
- R9-DRIFT OK: 67 sites scanned. No fixture pollution: worktree `.git/config` has no injected filter/diff.external/fsmonitor/attributesFile; no `/tmp/PWNED*`; no staged deletions; only untracked = peer reviewers' r13 files.
- Non-vacuity independently verified: (a) plain `git status` clean-filter RCE reproduced (marker fired) and blocked by `--attr-source=<empty>`; (b) extracted guard rule-4 genuinely FAILS on an injected un-hardened `git status` (doc-budget.sh); (c) R7-F1 positive-control repoint to `git ls-files --others` is CORRECT — review_git now also carries inline `-c core.fsmonitor=`, so the old module-load `git status` control would be MASKED; moving it to the non-review_git ls-files path keeps the env-pin control load-bearing.
- Retired-file lifecycle correct: present+marker→removed (both files), present-no-marker→kept, absent→noop, worktree-dirty→kept (not abort; abort path is F3 staged-non-deletion index, verified).
- automation-doctor standalone inline `_et="$(git hash-object -t tree /dev/null||echo 4b82…)"` path works with no git-harden.sh sibling.

## DEFECTS: 2 (highest MED)

### [MED] R12 `--attr-source=<empty-tree>` on `git status` reports FALSE-DIRTY on normal projects using a benign `.gitattributes` clean filter / EOL-normalization / git-lfs
- file: scripts/automation-doctor.sh:497, scripts/collect-review-context.sh:25,432,1232,1325, scripts/write-session-checkpoint.sh:69, scripts/micro-check.sh:66, tools/ai-home:56, tools/ai-rebuild-plan:119, tools/ai-tmux-worktree:71, tools/workspace-scan:83.
- one-line: forcing attributes from the empty tree disarms the RCE but ALSO disables benign clean/EOL/lfs filters, so `git status` sees filtered files as modified — a genuinely-clean tree is reported dirty.
- repro:
  ```
  R=$(mktemp -d)/repo; mkdir -p "$R"; cd "$R"; git init -q; git config user.email t@e.x; git config user.name T
  printf '*.txt filter=norm\n' > .gitattributes
  git config filter.norm.clean 'tr -d "\r"'; git config filter.norm.smudge cat
  printf 'a\r\nb\r\n' > data.txt; git add .gitattributes data.txt; git commit -qm init
  git status --short            # EMPTY  (true state = clean)
  ET=$(git hash-object -t tree /dev/null); git --attr-source="$ET" status --short   # ' M data.txt'  (false-dirty)
  bash scripts/automation-doctor.sh | grep 'working tree'   # '[warn] working tree has uncommitted changes'
  ```
- impact (NORMAL project class — git-lfs is the canonical victim: EVERY lfs blob shows ` M`): automation-doctor PASS→WARN on a pristine checkout; ai-tmux-worktree removability → permanent `keep:uncommitted` (worktree never GC'd — a real leak, ties to tmux-worktree-lifecycle-gaps backlog); collect-review-context tree-churn/micro-work scope audit polluted with dozens of false modifications; write-session-checkpoint false dirty. Gate VERDICT is NOT flipped (verify+review based; these status paths are report_only/advisory), so not HIGH; no security break. But it is an undocumented, untested behavioral regression introduced by this commit (pre-R12 these were plain filter-aware `git status`).
- fix: at minimum DOCUMENT the tradeoff at each site (comments only mention the RCE, never the false-dirty side effect) and add a fixture asserting a benign-clean-filter/lfs project stays "clean". Better: for the purely-informational verdicts (doctor clean-check, tmux-worktree removability) detect a `filter=`/lfs `.gitattributes` and fall back to filter-aware status (accepting the informational-only exposure) or annotate "status over-reported under attr-source hardening", so a legitimate lfs repo is not permanently un-GC-able and not perpetually warned.

### [LOW] AI_AUTO_TEMPLATE_VERSION retire guard regex is unanchored — wrongly removes a project file whose FIRST LINE merely starts with a date
- file: tools/ai-auto:81 — `AI_AUTO_TEMPLATE_VERSION) [[ "$first" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2} ]] ;;`
- one-line: intent is "bare version string" but the pattern is not end-anchored, so a first line like `2026.06.30 meeting notes` matches and the file is git-rm'd.
- repro: temp repo, commit `AI_AUTO_TEMPLATE_VERSION` whose 1st line = `2026.06.30 meeting notes`; `ai-auto setup` STAGES `D AI_AUTO_TEMPLATE_VERSION` (should be KEPT). Reproduced.
- severity: LOW — a project authoring a file literally named `AI_AUTO_TEMPLATE_VERSION` with a date-prefixed first line is near-impossible; removal is only STAGED (operator reviews) and idempotent. Still a real gap vs stated intent and vs the exact-string PATCH_NOTES marker.
- fix: anchor to a full-line bare version: `^[0-9]{4}\.[0-9]{2}\.[0-9]{2}[0-9.]*$` (optionally also require the file be single-line).
