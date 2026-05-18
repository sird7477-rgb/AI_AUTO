# High-Risk Plan Diagram Starter

Use this starter for plans that touch credentials, production data, live
deployment, trading, migrations, external side-effect APIs, or user-visible
operations.

## Execution Flow

```mermaid
flowchart LR
  Interview[Interview] --> Plan[Markdown Plan]
  Plan --> RiskRegister[Risk Register]
  Plan --> Diagrams[Mermaid / Structurizr]
  RiskRegister --> Gate{Execution Gate Approved?}
  Diagrams --> Gate
  Gate -- No --> Blocked[Blocked / Revise Plan]
  Gate -- Yes --> DryRun[Dry Run / Read-Only Run]
  DryRun --> Evidence[Evidence Review]
  Evidence --> Promote{Promotion Gate Approved?}
  Promote -- No --> Revise[Revise Plan]
  Promote -- Yes --> LimitedLive[Limited Live Execution]
  LimitedLive --> Monitor[Monitoring / Operator Review]
  Monitor --> Stop{Stop Condition Hit?}
  Stop -- Yes --> Rollback[Stop / Rollback]
  Stop -- No --> Evidence
```

## Execution State Gate

```mermaid
stateDiagram-v2
  [*] --> Draft
  Draft --> Reviewing
  Reviewing --> ApprovedForPlanning
  ApprovedForPlanning --> ApprovedForExecution
  ApprovedForExecution --> DryRun
  DryRun --> EvidenceReview
  EvidenceReview --> ReadOnlyProduction
  EvidenceReview --> Blocked
  ReadOnlyProduction --> LimitedLive
  LimitedLive --> Monitored
  Monitored --> Verified
  Monitored --> StopTriggered
  StopTriggered --> Rollback
  Rollback --> Draft
  Rollback --> Abandoned
  Abandoned --> [*]
```

## Boundary Map

Use Mermaid for small systems and Structurizr DSL for durable architecture.

```mermaid
flowchart TB
  User[Operator / User]
  Agent[AI_AUTO / Agent]
  Repo[(Repository Docs And Code)]
  Secrets[(Credentials / Secrets)]
  External[External System]
  Production[Production / Live Side Effects]

  User --> Agent
  Agent --> Repo
  Agent -. approval required .-> Secrets
  Agent -. gated side effect .-> External
  External -. live impact .-> Production
```

## Required Gate Fields

- approval owner
- allowed execution mode
- blocked actions
- credential boundary
- production/data boundary
- rollback or stop condition
- evidence required before promotion
- monitoring owner
