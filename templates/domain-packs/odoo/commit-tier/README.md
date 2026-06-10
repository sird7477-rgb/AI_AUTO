# Odoo Commit-Tier Static Checks (OCA, off-the-shelf)

The **commit tier** of the validation stack: fast, per-file static checks that run
before commit and act as a cheap pre-filter for the push-tier registry-load gate
(`../validation-harness/`). It adopts off-the-shelf OCA tools — **do not build a
custom static lint**.

## Tiers
```
commit  → OCA static (this dir): manifest/XML/CSV/PO hygiene, dup id/field,
          deprecated nodes, odoolint — seconds, advisory
push    → ../validation-harness/: registry load (-i/-u) on parity-pinned Odoo 19
          — definitive for view-inheritance/field/registry/NOT-NULL (T1/T2/T3/T7)
merge   → odoo.sh staging + AI review-gate — final, data-baseline
```

## What it catches / does NOT
- **Catches (commit-fast):** `manifest-*`, `xml-syntax-error`, `xml-duplicate-record-id`,
  `xml-duplicate-fields`, deprecated tree/qweb/chatter nodes, CSV/PO errors, and the
  `odoolint` Odoo-specific checks (incl. a subset of deprecated APIs).
- **Does NOT catch (needs push tier):** view-inheritance anchor resolution (**T2 — 0/8
  statically**), renamed/removed field/model/API schema (**the bulk of T1**),
  post-install test/demo/SQL-NOT-NULL load errors (**T4/T5/T7**), and
  cross-file/cross-module duplicate fields/labels (**partial T6**).
- **A clean commit-tier pass does NOT prove installability.** Always run the push
  tier for changed addon view/model XML.

## Adopt (opt-in; no installs during onboarding)
```bash
cp templates/domain-packs/odoo/commit-tier/.pre-commit-config.yaml .   # to repo root
cp templates/domain-packs/odoo/commit-tier/.pylintrc .                 # to repo root
pip install pre-commit          # pylint-odoo v10 needs pylint v4
pre-commit install
pre-commit run --all-files      # first pass
```
pre-commit fetches the pinned tool versions into isolated venvs — no global installs.

## Caveats
- **pylint false positives:** the config runs only `odoolint` (`--disable=all
  --enable=odoolint`) so plain-pylint `import-error`/`no-member` do not fire when
  Odoo is not importable. This suppression is load-bearing; keep it.
- **Auto-fix is opt-in:** do not enable fixer hooks that silently rewrite files.
- **Pins:** `OCA/pylint-odoo@v10.0.2` (Odoo 19.0, pylint v4),
  `OCA/odoo-pre-commit-hooks@v0.2.22`. Bump only with evidence.
- See `OCA/oca-addons-repo-template` for full CI wiring patterns.
