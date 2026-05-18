# <Name> Spec

## Source Drawing

- Editable: `<file>.excalidraw`
- Export: `<file>.svg`
- Related plan: `../02-plan.md`
- Generated from drawing: yes
- Human reviewed: no
- Status: draft

## Purpose

State what the drawing is meant to decide, explain, or constrain.

## Layout

Describe the visible regions from top to bottom and left to right.

## Components

| Component | Label In Drawing | Responsibility | Source Of Truth |
| --- | --- | --- | --- |
| `<component>` | `<label>` | `<responsibility>` | `<plan/spec/code>` |

## States

List all applicable states:

- loading
- empty
- normal
- warning
- error
- disabled
- review
- approved

## Actions

| Action | Actor | Allowed Effect | Required Confirmation |
| --- | --- | --- | --- |
| `<action>` | `<user/system/agent>` | `<effect>` | `<none/confirm/gate>` |

## Risk Gates

List actions that require approval, confirmation, rollback support, credential
access, production access, trading/order safety checks, or data-boundary checks.

## Constraints

List responsive layout rules, prohibited UI behavior, data boundaries,
implementation constraints, and non-goals.

## Open Questions

Use this section when the drawing is ambiguous. Do not invent behavior.

## Acceptance Criteria

List the checks required before this spec can drive implementation.

## Drift Check

- Drawing still matches plan: unknown
- Spec still matches implementation: unknown
- Last reviewed: `<YYYY-MM-DD>`
