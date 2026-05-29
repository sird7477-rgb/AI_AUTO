# AI_AUTO 19 TODO Operational-Clear Ralph Plan

Date: 2026-05-30

## Goal

Move all 19 remaining active or policy-attention TODO items to
`operational_clear`, one item at a time, with micro implementation and
verification loops. A TODO is clear only when the actual operating surface is
wired, verified, its backlog status is `operational_clear`, and it no longer
appears in active or policy-attention output.

## Clearance Definition

An item may be marked `operational_clear` only when all apply:

1. A real caller, command, script path, report section, or user workflow invokes
   the behavior.
2. Failure behavior is bounded: fail-closed where authority matters, or
   warning-only/pass-through where startup/user flow must not be blocked.
3. Tests or smoke checks verify the caller path, not only pure contract helpers.
4. Related docs, template copies, installer/global helper surfaces, and patch
   notes are synchronized when touched.
5. The canonical backlog row status is `operational_clear`.
6. `python3 scripts/todo-report.py --fail-on-active` no longer reports the item
   in active or policy-attention buckets.

## Grouping

### Small

Small items are local policy/reporting/workflow surfaces with limited blast
radius. Claude review is optional unless the micro diff changes review authority
or startup behavior.

| ID | Item | Why Small |
| --- | --- | --- |
| `ST-P1-14` | Product challenge planning gate | Planning policy/routing only. |
| `ST-P1-16` | Phase/scope guard workflow | Local scope classification and deferral checks. |
| `ST-P1-17` | Review finding revision loop | Review-loop reporting/task semantics only. |
| `ST-P1-18` | Tool availability and adoption status workflow | Doctor/status/reporting surface only. |

`ST-P1-18` is intentionally first because its operating surface is limited to
the existing `automation-doctor.sh` and `bootstrap-ai-lab.sh` command-status
output. It must not introduce or depend on the broader central manifest tooling
tracked by `SA-P1-02`.

### Medium

Medium items touch review authority, template/global parity, completion routing,
or verification breadth. Claude review is required before item clearance.

| ID | Item | Why Medium |
| --- | --- | --- |
| `SA-P1-01` | Template Lifecycle | Template ownership and downstream patch safety. |
| `SA-P1-02` | Global Tools | Installer/doctor/bootstrap/global helper consistency. |
| `SA-P2-01` | Verify Coverage | Verification gate behavior. |
| `ST-P1-05` | Benchmark auto-capture baseline/gate | Optional benchmark policy can affect readiness claims. |
| `ST-P1-07` | Persona lens and review-gate enforcement | Review-gate authority and routing. |
| `ST-P1-09` | Project AI_AUTO update visibility | Startup/status notice behavior. |
| `ST-P1-10` | High-risk relationship clearance | Authority/startup/vault risk closure. |
| `ST-P1-11` | Medium-risk relationship clearance | Review/template/degraded-trust risk closure. |
| `ST-P1-12` | Low-risk relationship cleanup | Guidance/rebuild/display-only safety closure. |
| `ST-P1-13` | Planning visualization workflow promotion | Workflow routing and artifact ownership. |
| `ST-P1-19` | Completion-pack trigger and lens routing audit | Completion-pack routing and review lens semantics. |

### Large

Large items touch runtime collection, external tools/browsers, vault side effects,
or self-demo execution. Claude review is required, and a second reviewer is used
when available.

| ID | Item | Why Large |
| --- | --- | --- |
| `SA-P1-03` | Artifact Sync | Runtime artifact scanning and final-answer traceability. |
| `SA-P1-04` | Self-Demo | Runtime demo runner/global helper. |
| `ST-P1-08` | Obsidian pending-output auto-push | Vault write/push approval and pending-output discovery. |
| `ST-P1-15` | UI/browser QA evidence workflow | Browser/CDP/session safety and evidence authority. |

## Execution Order

1. `ST-P1-18` tool adoption status.
2. `ST-P1-16` phase/scope guard.
3. `ST-P1-17` review revision loop.
4. `ST-P1-14` product challenge gate.
5. `SA-P1-01` template lifecycle.
6. `SA-P1-02` global tools.
7. `SA-P2-01` verify coverage.
8. `ST-P1-12` low-risk relationship cleanup.
9. `ST-P1-11` medium-risk relationship clearance.
10. `ST-P1-10` high-risk relationship clearance.
11. `ST-P1-13` planning visualization workflow.
12. `ST-P1-19` completion-pack routing.
13. `ST-P1-07` persona lens/review-gate enforcement.
14. `ST-P1-09` update visibility.
15. `ST-P1-05` benchmark baseline/gate policy.
16. `SA-P1-03` artifact sync.
17. `SA-P1-04` self-demo runtime.
18. `ST-P1-08` Obsidian auto-push.
19. `ST-P1-15` UI/browser QA evidence.

## Micro Loop

For each item:

1. Inspect current caller and plan references.
2. Add the smallest caller/runtime/reporting surface needed.
3. Add or update targeted tests for the caller path.
4. Update backlog status to `operational_clear` only after caller-path
   verification evidence exists.
5. Run targeted tests, `python3 scripts/todo-report.py`, and
   `./scripts/verify.sh`. During intermediate Ralph iterations, `verify.sh` may
   still fail at the canonical TODO report because later items remain; the item
   is clear only if all earlier gates pass and the current item is absent from
   active or policy-attention output.
6. For medium/large items, run Claude review and resolve findings.
7. Clear only when local verification and reviewer verdicts all agree.

## Stop Conditions

- Stop and report if a required external credential, destructive operation, or
  production side effect is needed.
- Do not clear an item by weakening the TODO guard.
- Do not clear an item by moving unfinished work into prose-only future notes.
