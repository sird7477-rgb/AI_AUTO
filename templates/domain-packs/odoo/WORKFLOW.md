# Odoo Workflow Pack

Use this as source material for the target project's `docs/WORKFLOW.md` after
confirming that the project is Odoo-based.

## Onboarding Questions

- Which Odoo version is targeted?
- Is the project locked to one major version, for example Odoo 19?
- Which addon directories are in scope?
- Which modules are owned by this project?
- How is the Odoo runtime started locally?
- How is the test database created and destroyed?
- Which command installs or updates the changed module?
- Which business flow is the required smoke check?
- Are enterprise/private addons required to run tests?
- Which localization baseline applies, for example Korean `ko_KR`, KRW, and
  10% VAT?
- Are there project-specific deployment, SSH, branch, or commit rules that must
  stay in the target project instructions?
- For Odoo 19 on odoo.sh, where is the project-local SSH/access runbook, and how
  are temporary admin passwords requested, used, and revoked?
- If odoo.sh SSH is run from WSL after setup in Windows PowerShell, has the
  operator verified that the required key exists in WSL `~/.ssh` or has been
  copied/imported there with correct permissions? Keep the private key content
  out of docs, prompts, logs, and feedback queues.
- Are Playwright checks required, and which environment variables provide the
  base URL, login identity, password source, and browser project?

## Development Loop

0. **Consult the KB first** (before schema/view/field/security work): read the relevant
   `Odoo19_Docs_KB/slim/<topic>` navigation file first (token-cheap heading/signature tree),
   and the project's own `Odoo.sh KB/` decision guides. Read `raw/<topic>` only when slim is
   insufficient or a security/implementation judgment is needed. **The KB is advisory — current
   repo evidence (actual code, registry-load validation, tests) always overrides a KB note;
   never let a stale slim entry justify code that contradicts the live module.** To check
   standard Odoo *code* (exact field/method names, selection values, view ids/xpath targets),
   grep the local Odoo source first — the harness ships the full community/enterprise trees on
   disk (`ODOO_COMMUNITY`/`ODOO_ENTERPRISE`, e.g. `<00. DATA>/01. Odoo.19(커뮤니티)/{odoo,addons}/`);
   GitHub raw or the odoo.sh build-server source is only the fallback when no local source is configured.
1. Identify the affected module, model, view, security file, report, or data
   file.
2. Keep the change inside the confirmed addon scope.
3. Update or add tests when project test infrastructure exists.
4. Run the project Odoo verification command.
5. Run the business smoke check when the change affects user workflow.
6. Run the standard review gate before presenting a commit candidate.

## Local UI Preview — trigger: "로컬띄워"

When the user asks to preview the project in a browser — trigger phrases
**"로컬띄워"**, "로컬 띄워", "serve 띄워", "로컬 serve", "UI 확인" — start the harness
`serve.sh` so they can verify form layout and per-field behavior by hand before pushing:

- Run `serve.sh <project_repo> [changed modules]` in the BACKGROUND. It is a long-running
  foreground HTTP server, so never run it blocking in the session — background it, poll
  until the port answers, then report the URL. On WSL2 the FIRST all-module + enterprise
  load can take several minutes (the registry build + first `/web` asset compile); poll
  patiently (wait for Odoo's `HTTP service (werkzeug) running`) before concluding failure.
  serve.sh disables Odoo's time watchdog by default so this slow first load no longer
  restart-loops (`ODOO_SERVE_LIMIT_*` to tune; memory stays capped, not unlimited).
- Report `http://localhost:<port>` (default 8069, `ODOO_SERVE_PORT`) and the login
  `admin / admin`. The user clicks through the actual forms; you do not drive the UI.
- No module argument updates the git-diff changed modules; pass a module name explicitly
  for a brand-new (untracked) module. It clones the warm base into a persistent `serve`
  DB (records the user enters persist; `ODOO_SERVE_FRESH=1` resets it).
- Stop it by killing the background run (the user can also Ctrl-C their own foreground run).
- The harness lives outside the repo (`ODOO_HARNESS_DIR` / the project's `00. DATA/harness`);
  if it is not configured, say so rather than guessing a path.

## Project-Specific Rules

Keep reusable Odoo guidance separate from project-specific operations:

- reusable pack: Odoo version discipline, addon-scope rules, verification
  patterns, localization prompts, and review checklist
- target project files: customer-specific modules, odoo.sh URLs, SSH keys,
  branch routing, commit approval rules, attachment/document automation rules,
  temporary admin password procedures, Playwright environment variables, and
  production-like access procedures

## Odoo-Specific Completion Evidence

Report:

- Odoo version and module names
- changed addon paths
- install/update/test command used
- database strategy used for verification
- localization baseline used for demo/test data
- smoke scenario result
- any skipped checks and why they were unavailable

## Default Non-Goals

Unless explicitly requested, do not:

- change production deployment settings
- perform real production database operations
- add broad migration tooling
- introduce new external services
- change unrelated addons
- harden infrastructure beyond the requested development workflow
