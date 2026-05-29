# AI_AUTO External Tool Install Evaluation - 2026-05-29

## Scope

This evaluates optional external tools before any required-gate adoption.
`hyperfine` and `shellcheck` were installed only after explicit user approval.
ShellCheck is now promoted to a required AI_AUTO source-checkout gate at warning
severity. Hyperfine remains observational benchmark capture and is not a
performance gate.

## Local Evidence

- Installed and available now: `jq`, `rg`, `hyperfine 1.18.0`,
  `shellcheck 0.9.0`.
- Not available on `PATH` in this environment: `shfmt`, `ruff`,
  `markdownlint-cli2`, `actionlint`, `semgrep`, `cloc`, `tokei`.
- No `.github` directory is present, so GitHub Actions linting has no local
  target today.

Post-review install notes:

- `hyperfine` was installed with `apt-get install -y hyperfine`.
  Rollback path: `apt-get remove -y hyperfine`.
- `shellcheck` was installed with `apt-get install -y shellcheck`.
  Rollback path: `apt-get remove -y shellcheck`.

Advisory run evidence:

- `hyperfine --version` reports `hyperfine 1.18.0`.
- `shellcheck --version` reports `shellcheck 0.9.0`.
- `shellcheck -S warning scripts/*.sh templates/automation-base/scripts/*.sh`
  returns clean and is enforced by `./scripts/verify.sh`.
- Full ShellCheck output still has info/style findings. Those remain cleanup
  candidates and are not required for this gate.

## Source Notes

- ShellCheck's project describes it as static analysis for shell scripts and
  focuses on syntax, semantic issues, and subtle shell pitfalls:
  https://github.com/koalaman/shellcheck
- `shfmt` is provided by `mvdan/sh`, a shell parser and formatter project:
  https://github.com/mvdan/sh
- `hyperfine` is a command-line benchmarking tool with warmup and run-count
  controls:
  https://github.com/sharkdp/hyperfine
- Ruff is a Python linter and formatter:
  https://github.com/astral-sh/ruff
- `markdownlint-cli2` is a configurable Markdown/CommonMark lint CLI:
  https://github.com/DavidAnson/markdownlint-cli2
- Semgrep supports local CLI scans, but `semgrep ci` is tied to account-backed
  organization policies:
  https://semgrep.dev/docs/getting-started/cli
- `cloc` and `tokei` are source line counting tools:
  https://github.com/AlDanial/cloc
  https://github.com/XAMPPRocky/tokei

## Scoring

Score fields are 1-5: repo fit, signal, install burden, churn risk, required
now, and rollback simplicity. Higher total is better. `install burden` and
`churn risk` are reverse-scored, so 5 means low burden or low churn risk.

| Tool | Repo Fit | Signal | Install Burden | Churn Risk | Required Now | Rollback | Total | Decision |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `shellcheck` | 5 | 5 | 3 | 4 | 4 | 5 | 26 | installed required warning-severity shell gate |
| `hyperfine` | 4 | 4 | 3 | 5 | 3 | 5 | 24 | installed optional benchmark capture; not a required gate |
| `shfmt` | 4 | 3 | 3 | 2 | 2 | 4 | 18 | excluded: no bulk formatting; ShellCheck warning gate covers actionable risk |
| `ruff` | 3 | 4 | 3 | 3 | 2 | 4 | 19 | reference-only until Python policy and surface grow materially |
| `markdownlint-cli2` | 4 | 3 | 2 | 2 | 2 | 4 | 17 | excluded as required gate; doc-budget targets the real guidance problem |
| `actionlint` | 1 | 3 | 3 | 5 | 1 | 5 | 18 | excluded; no `.github` workflows present |
| `semgrep` | 3 | 4 | 2 | 2 | 1 | 3 | 15 | excluded from this testbed; reopen only under a security-specific plan |
| `cloc` / `tokei` | 2 | 2 | 3 | 5 | 1 | 5 | 18 | excluded; existing doc-budget and `find` cover current counting needs |

## Adoption Order

1. `shellcheck` is installed and promoted to a required `verify` gate at warning
   severity.
2. `hyperfine` is installed; keep it as optional benchmark capture, not a
   required performance gate.
There is no remaining active adoption order. Do not report any other external
tool as a TODO. `ruff` may be re-evaluated only if the Python surface and
project policy materially change.

## Current Tool / Guidance Relationship

| Tool | Installed | Gate Status | Guidance Link |
| --- | --- | --- | --- |
| `shellcheck` | yes | required AI_AUTO source-checkout gate at `-S warning` | `verify.sh`, doctor/bootstrap prerequisites, README, template README, this evaluation |
| `hyperfine` | yes | observational benchmark evidence only | `benchmark-command.py`, benchmark plan/evidence docs, README, template README |
| `docker` | environment/runtime dependent | required smoke surface for Docker-backed checks | `verify.sh`, README |
| `claude` / `agy` | environment/runtime dependent | review-gate reviewer surface; degraded operation must be reported | `review-gate.sh`, review summary contracts |

## Excluded / Reference-Only Candidate Audit

- `shfmt`: excluded as a TODO. Bulk formatting has high churn and ShellCheck
  warning severity already catches the useful shell-risk class.
- `ruff`: reference-only, not a TODO. Reopen only if Python policy and code
  volume materially change.
- `markdownlint-cli2`: excluded as a required gate. It would turn long-form
  operational docs into style-exception maintenance; `doc-budget.sh` covers the
  current guidance-volume risk.
- `actionlint`: excluded while no `.github` workflow target exists.
- `semgrep`: excluded from this local automation testbed. Reopen only under a
  security-specific plan with rule scope and false-positive budget.
- `cloc` / `tokei`: excluded. Current counting needs are covered by
  `doc-budget.sh`, Python, `find`, and `rg`.
- `fd` / `yq`: excluded as install TODOs. Current search and structured-data
  needs are covered by existing tools.

## Minimum Approval Gate Before Install

Before installing any new candidate that is explicitly reopened by a later user
request:

- run an independent second opinion/review on the install need, scope, and
  rollback path
- choose install scope: local dev image, CI, project venv, or host package
- record rollback command or removal path
- run the tool in advisory mode first
- prove it catches one useful issue or produces a low-noise clean run
- keep `./scripts/verify.sh` passing without any remaining optional tool unless
  the project later promotes that tool to a required gate

## Recommendation

`shellcheck` is now required at warning severity. `hyperfine` remains
optional/observational. There are no remaining external-tool installation TODOs.
Other candidates are excluded or reference-only and must not appear in active
TODO reports.

Next optional cleanup TODO: triage ShellCheck info/style findings in small
batches if they block readability or future hardening. Do not bulk-format or
rewrite all shell scripts just to silence advisory output.
