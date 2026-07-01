# RED TEAM Round 11 (final gauntlet) — safety findings (feat/global-toolize @ 70fd6e5)

Scope: residual git-exec RCE; R10-hardened drift-guard soundness; setup/launcher/hooks
data-loss/engine-mutation/silent-skip; NON-git injection (commit msg / branch / path /
AGENTS.md / manifest / .omx into eval / %b / unquoted / sed / py subprocess); TOCTOU /
predictable-tmp; correctness (false pass / crash on edge cases). Read-only; all repros in
`mktemp -d` temp trees. This worktree's `.git/config` was NOT mutated. No marker files left
outside the temp dir.

## DEFECTS: 1 (highest LOW)

---

### D1 (LOW, LATENT — no active vuln) — R10 drift-guard hardening is INCOMPLETE: command-prefix and non-`review_git`-wrapper worktree-diff forms still scan to ZERO sites and pass clean

`scripts/verify-machinery.sh:7350-7354` (the `INVOKE` regex in the temp `git-harden-drift.py`).

R10 hardened the command-position matcher against `if/for/while/eval/xargs` and python
list-concat, and I confirmed ALL of those are now caught (plus `until/case/{...}/pipe/&&/$(...)`
/backtick — verified in a temp tree, guard returns rc=1 on each). BUT the R10 fix's prefix
alternation `\b(?:then|do|else|elif|eval|xargs)\b` does not cover two other idiomatic
command-position forms, so they still evade (guard prints `0 site(s) scanned … all hardened`,
rc=0):

EXACT REPRO (each planted as the only `git diff` in a temp `fake/scripts/t.sh`; run the guard
extracted verbatim from verify-machinery.sh):
- `time git diff --name-only HEAD`      → EVADES (`time` before git)
- `command git diff --name-only HEAD`   → EVADES (`command` before git)
- `env git diff --name-only HEAD`       → EVADES (`env` before git)
- `nohup git diff --name-only HEAD`     → EVADES
- `sudo git diff --name-only HEAD`      → EVADES
- `my_git diff --name-only HEAD`        → EVADES (any wrapper function NOT named `review_git`;
  `git` inside `my_git` has no word boundary and no command-position anchor before it)

Control (guard is otherwise live): the same battery's `git diff …`, `if …; then git diff`,
`for … do git diff`, `$(git diff …)`, `` `git diff …` ``, `foo | git diff`, `bar && git diff`,
`{ git diff …; }`, `case x in a) git diff …` are ALL caught. The shipped tree passes with
`50 site(s) scanned, all hardened`.

Impact: LATENT only. Grep over scripts/ hooks/ tools/ templates/domain-packs/ for
`(env|command|time|nohup|sudo|xargs).*git.*diff` and for any git wrapper other than review_git
is CLEAN — no shipped site uses these forms, so there is NO live clean-filter RCE today. But the
guard's sole purpose is to FAIL a FUTURE un-hardened worktree diff. A later author who writes
`env git diff --name-only "$base"` (common when pinning a var), or introduces a second git
wrapper `my_git()`, adds an un-hardened worktree clean-filter-RCE site and the guard stays GREEN.
This is the SAME class as R10-D1 (MED, latent); R10 fixed the forms it enumerated but did not
generalize, so the belt is still incomplete. Severity LOW because it is one step further removed
(both R10's forms and these are latent) and the wrapper-name case requires a deliberate new
abstraction.

Fix: generalize the command-position anchor instead of enumerating keywords — after stripping a
leading `(?:sudo|env|command|time|nohup|exec|builtin)\s+` run, require `(?:review_)?git` in
command position; and/or drop the command-position anchor entirely and post-filter comment/prose
lines (the line-is-comment skip already exists), since the guard already "errs toward FLAGGING."
For the wrapper case, additionally treat any `\w*git\b …\bdiff\b` invocation that is not literally
`review_git` as un-hardened unless it carries `--attr-source=`. Add `time git diff` /
`env git diff` / `my_git diff` as positive controls (b8) so the gap cannot reopen.

---

## Probes that came back CLEAN (exhaustive last-ditch effort, documented)

- **git-exec RCE class**: CONFIRMED CLOSED. Shipped tree passes the drift-guard (50/50 sites
  hardened); every engine worktree diff routes through `review_git` (scripts/git-harden.sh),
  whose central `--attr-source=<empty-tree> -c diff.external= -c core.fsmonitor=
  -c core.attributesFile=/dev/null` disarms clean/smudge/textconv/external drivers even on
  `--name-only/--stat/--quiet`; `--no-index` reads carry `--no-filters`. No git alias / `git()`
  function / second wrapper exists in the engine (grep clean). `core.fsmonitor` pinned empty via
  GIT_CONFIG_* (hooks/git-scrub.sh). No NEW reachable exec key found.
- **launcher/setup (tools/ai-auto)**: self-host guard tests EXISTENCE not exec-bit (`-f`, R3-1);
  atomic all-or-nothing `git rm` of the safe set; symlinked/worktree-modified managed files kept
  (`-L`/`cmp -s`/`diff --quiet`); dirty-index precheck; common-dir flock with scoped `2>/dev/null`
  and CLOEXEC-close of the lock fd; hook shims fail-closed (never clobber a custom hook, upgrade
  legacy engine bodies, warn+exit0 when engine hook missing/dir). Heredoc bakes only the trusted
  engine path. No data-loss / engine-mutation / TOCTOU found.
- **hooks (pre/post-commit) + git-scrub**: canonical GIT_* + GIT_CONFIG_KEY_*/VALUE_* + GIT_TRACE*
  scrub single-sourced; pytest exit-5 not fail-closed; engine-vs-derived split correct;
  onboarding warn-and-allow disclosed (not silent). post-commit advisory-only, always exit 0.
- **NON-git injection**: commit msg / branch / path / AGENTS.md / .omx content is written into the
  review-context markdown or matched in `case`/glob (subject side, not pattern side) — never
  reaches eval / `printf %b` / unquoted expansion / `bash -c`. `REVIEW_UNTRACKED_ALLOWLIST` globs
  are operator-controlled and applied as case PATTERNS against attacker paths on the SUBJECT side.
  The verify-override file is parsed with `sed -n 's/^k=//p'`, never sourced/eval'd. micro-unit
  JSON is `json.load` with a broad except. No predictable /tmp (all `mktemp -d`).
- **correctness**: verify-scope engine detection (`-ef` toplevel), gate red-signal handling,
  override→proceed_degraded, cwd-removed→exit 75 deferral, empty-repo/detached-HEAD guards
  (`has_head_commit`, `rev-parse --verify`) all sound. The doctor auto-mode uses `-x` on tools to
  detect the engine (a lost exec bit → auto-picks `project`), but `--home` overrides and this is a
  convenience heuristic, not a security/verdict gate — noted, not a finding.
