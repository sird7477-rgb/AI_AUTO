# External Gemini Runner / WSL Docs — Root-Cause and Validity Analysis (2026-06-09)

Queue item: `review-gate:external-gemini-runner-wsl-docs` (high, improvement),
sourced from `Project_corini/.omx/feedback/queue.jsonl` as a
`user-request-ai-auto-main-queue` intake.

## Reproduction context

The incident occurred when an AI_AUTO-installed repo was launched from the
**Codex desktop app**: the active principal was Codex, the Claude reviewer was
unavailable, and the review gate fell back to preparing an external Gemini
runner. Gemini CLI then failed on its Docker sandbox.

## Method

The item's `resolution` field bundles several distinct claims. Each was checked
against AI_AUTO main (`ai-lab`), decomposed as claims ①–⑤, and given an
independent root-cause + validity verdict.

## Per-claim findings

The machinery the item references all exists:
`scripts/run-ai-reviews.sh:9` (`REVIEW_EXECUTION_MODE`), `:14`
(`GEMINI_REVIEW_COMMAND=agy` default) → `:34` (`RUNTIME_ADAPTER_AGY_COMMAND`),
`:1319` (`RUN_CLAUDE_REVIEW=0`), `:208-209` (`write_external_runner` →
`.omx/external-review/run-reviewers-latest.sh`).

| # | Claim | Verdict | Rationale |
|---|-------|---------|-----------|
| ① | Document `REVIEW_EXECUTION_MODE=external` | **Already done** | `docs/MULTI_AI_COLLABORATION.md:276-296`, `docs/CURRENT_STATE.md:99,518,583`, `docs/AUTOMATION_OPERATING_POLICY.md:645`. |
| ② | Document the generated runner + summarize/gate flow | **Already done** | `docs/MULTI_AI_COLLABORATION.md:296` covers the runner's root resolution, tee output, and summary. |
| ③ | Document `RUN_CLAUDE_REVIEW=0` | **Minor gap** | Present in code (`:1319`) but only `RUN_CODEX_FALLBACK_REVIEW=0` was documented. Added to `WORKFLOW.md` + `MULTI_AI_COLLABORATION.md`. |
| ④ | Document `GEMINI_REVIEW_COMMAND=gemini` / `RUNTIME_ADAPTER_AGY_COMMAND=gemini` as the path | **Rejected — conflicts with routing contract** | See below. |
| ⑤ | Document + handle the Gemini Docker-sandbox failure / WSL no-sandbox path | **Genuine gap (docs + code)** | See below. |

## ④ — Why the `=gemini` recommendation was rejected

`docs/AI_MODEL_ROUTING.md:101-103` states Gemini is invoked **only via `agy`**
(the sole path to gemini 3.5); `gemini -m` is forbidden and `agy` has no model
selector, so a Gemini principal is **class-fixed**. The adapter's
`run_readonly_agy` appends `--model "${model}"` when the command's help supports
it (`scripts/ai-runtime-adapter.sh:271-273, 297-299`). Setting
`RUNTIME_ADAPTER_AGY_COMMAND=gemini` would therefore make the real invocation
`gemini --model <x>` — exactly the forbidden path — and break class-fixing.

**Decision:** do not document `=gemini` as the recommended path. `agy` stays the
default/recommended `GEMINI_REVIEW_COMMAND`. Raw `gemini` is documented only as a
degraded last resort for environments without `agy`, with the explicit caveat
that it is not class-fixed. This is recorded here as a durable "do not do this"
decision; the corini queue item is resolved pointing at this report.

## ⑤ — Root cause and fix

Root cause of the original incident: `run_readonly_agy` adds `--sandbox` whenever
the command's help advertises it (`scripts/ai-runtime-adapter.sh:285-287,
311-313` pre-fix). For the official `gemini` CLI, `--sandbox` boots a
Docker/podman container (or macOS Seatbelt). On WSL or a desktop runtime with no
container runtime, the sandbox image cannot be pulled/started and the review
dies. There was no mitigation and no documentation. The adapter's own header
comment (`:19-20`) already states agy/Gemini are not treated as a filesystem
sandbox boundary, so passing a Docker `--sandbox` was also internally
inconsistent.

Fix (implemented, tracked as `ST-P1-50`):

- `agy_command_sandbox_ok()` gates `--sandbox` for the raw `gemini` command only:
  honor case-insensitive `GEMINI_SANDBOX=0|1`, else auto-detect a *usable*
  runtime — `container_runtime_usable` probes `docker`/`podman` with a
  timeout-bounded `info` so an installed-but-down daemon (the common WSL/desktop
  state, flagged by the Codex reviewer) does not count — plus macOS Seatbelt,
  else skip. `agy` and other wrappers are unaffected. Dropping `--sandbox` is
  safe because the reviewer path is read-only.
- Mirrored to `templates/automation-base/scripts/ai-runtime-adapter.sh`
  (template-owned per the status manifest).
- Deterministic self-test in `verify-machinery.sh` (both copies):
  `GEMINI_SANDBOX=0` → `--sandbox` absent, `GEMINI_SANDBOX=1` → present.
- Docs: `docs/WORKFLOW.md` (+ template copy) and `docs/MULTI_AI_COLLABORATION.md`
  describe the external/Claude-unavailable path, `RUN_CLAUDE_REVIEW=0`, the raw
  `gemini` caveat, and the sandbox/WSL handling.
- Template version `2026.06.09.0` + matching PATCH_NOTES entry.

## Net outcome

- ①② were already shipped; the item overstated the documentation gap.
- ③⑤ were the real work and are implemented under `ST-P1-50`.
- ④ is rejected on routing-contract grounds and recorded here.
