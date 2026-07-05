# AI_AUTO AUD-7 repro-fidelity plan

## Contract

Add the repro-fidelity doctrine to guidance and enforce root-cause claim artifacts
through the existing checksheet runner. This is not a new tool and must not use an
LLM to judge whether reproduction fidelity is true.

## Design Decisions

- Guidance marker: add `AUD-7-REPRO-FIDELITY-DOCTRINE` to both `docs/WORKFLOW.md`
  and `AGENTS.md` with the same rule: high-confidence root-cause language is allowed
  only when reproduction matches the user-observed symptom; proxy reproduction keeps
  the claim as a hypothesis.
- Runner surface: extend `scripts/checksheet-run.py` with a deterministic
  file-based oracle named `root_cause_fidelity`.
- Artifact format: root-cause claim artifacts are JSON files with required string
  fields `observed_symptom`, `reproduction`, and `fidelity`. `fidelity` is
  author-declared and must be `yes` or `no`.
- Contradiction rule: if `fidelity=no`, the artifact must not use high-confidence
  root-cause language in `claim`, `conclusion`, `summary`, or `root_cause`. Hedges
  such as "hypothesis"/"미확정"/"가설" are allowed.
- Existing runner discipline remains: selftest must prove the good artifact passes
  and a bad `fidelity=no` plus confirmed-language artifact fails before real
  checksheets are trusted.

## Files

- `AGENTS.md`
- `docs/WORKFLOW.md`
- `scripts/checksheet-run.py`
- `tests/test_checksheet_run.py`
- `scripts/verify-machinery.sh`

## Acceptance Mapping

- Missing 3-field contract fails via tests for absent `observed_symptom`,
  `reproduction`, or `fidelity`.
- `fidelity=no` plus confirmed/root-cause language fails.
- `fidelity=yes` plus confirmed/root-cause language passes.
- `WORKFLOW.md` and `AGENTS.md` marker parity is tested in verify machinery.
- No LLM fidelity judgement is introduced; only declared fields and contradiction
  patterns are checked.
