# Benchmark Evidence - verify-smoke-installed

- status: `pass`
- verdict: `observed`
- command: `.venv/bin/python -c 'print('"'"'ok'"'"')'`
- captured_at: `20260528T203315Z`
- tool: `hyperfine` available=`True` version=`hyperfine 1.18.0`
- git_commit: `fb7cd6cc04825d800db24df5ef01c4884c1e5e4c`
- metric: `runtime_ms`
- sample_count: `3`
- measured_ms: `17.736`
- raw_output_json: `plans/benchmarks/20260528T203315Z-verify-smoke-installed.hyperfine.json`
- reason: measurement_recorded_without_readiness_claim

This evidence is observational. It does not replace `./scripts/verify.sh` or `./scripts/review-gate.sh`.
