# AI_AUTO Benchmark Baseline - 2026-05-28

## Scope

This artifact records the first measured runtime baseline for SA-P1-06. It is
not a readiness approval, tool adoption decision, or replacement for
`./scripts/verify.sh` / `./scripts/review-gate.sh`.

## Representative Workflow

- Scenario: self-demo contract suite validates representative workflow evidence.
- Command: `.venv/bin/python -m pytest tests/test_self_demo_contracts.py -q`
- Environment: `/root/workspace/ai-lab` local venv, 2026-05-28 Asia/Seoul.
- Measurement method: Python `time.perf_counter()` around the command.
- Sample count: 5.

## Measurements

| Sample | Wall Seconds | Exit |
| --- | ---: | ---: |
| 1 | 0.238 | 0 |
| 2 | 0.257 | 0 |
| 3 | 0.236 | 0 |
| 4 | 0.356 | 0 |
| 5 | 0.305 | 0 |

Summary:

- Minimum: 0.236 seconds
- Median baseline: 0.257 seconds
- Mean: 0.278 seconds
- Maximum: 0.356 seconds

## Contract Record

- Metric: `self_demo_contract_pytest_wall_seconds`
- Direction: `lower_is_better`
- Baseline: 0.257 seconds
- Measured: 0.257 seconds
- Threshold source: `project_baseline`
- Regression-watch threshold: 0.500 seconds
- Threshold rationale: local threshold above the observed max 0.356 seconds;
  this is for future regression detection only.
- Contract verdict: `benchmark_pass`
- Readiness supported: false, because no readiness claim is made by this
  baseline artifact.

## Boundary

This baseline is repo-local and workflow-specific. It is not a common industry
standard. Future benchmark work may add established standards only when a
credible external reference exists for the exact workflow being measured.
