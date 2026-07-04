# SPEC-AUD-REG Plan: closed-defect regression registry

## Contract

SPEC-AUD-REG adds a registry layer that reasserts closed high/critical defects
before merge and before the blue/red game. It must not invent a new regression
engine or claim more machine authority than it proves. The host is the existing
`checksheet-run` lane; `verify-machinery.sh` remains the all-or-nothing suite,
not an addressable fixture backend.

## Design Decisions

1. Add a `--regression-registry` mode to `scripts/checksheet-run.py`. The thin
   wrapper remains unchanged except for passing arguments through.
2. Store the seed registry as `checksheets/closed-defect-regression.registry.json`.
   Each item carries `id`, `source`, `severity`, `protects`, `closed_at`,
   `enforcement`, and a deterministic command `predicate`.
3. Use command predicates as the narrow extension point: JSON `argv` arrays only,
   no shell string, bounded timeout, repo-root working directory by default, and
   optional stdout/stderr substring checks. This lets the registry point at
   existing tests or cheap source guards without cloning `verify-machinery`.
4. Mechanized items must also define `non_vacuity`. The runner executes it and
   requires the declared adversarial result. If it does not fail as expected, the
   item is blocked as vacuous. Items without that proof are labeled
   `author_asserted`, never `mechanized`.
5. Extend `review-gate.sh`'s checksheet artifact gate to run changed
   `*.registry.json` files via `checksheet-run.sh --regression-registry` before
   external review.

## Verification Plan

- Unit tests for: valid registry passes, missing predicate fails completeness,
  vacuous mechanized item fails, bad normal predicate blocks, and author-asserted
  items do not claim mechanized status.
- `verify-machinery.sh` fixture for review-gate calling changed registry files
  with `--regression-registry` and blocking on failure before reviewers run.
- Existing checksheet fixtures remain green.

## Boundaries

- No LLM verdicts.
- No selector/tagging retrofit inside `verify-machinery.sh`.
- No claim that author-asserted seed entries are machine-enforced beyond their
  deterministic predicate.
