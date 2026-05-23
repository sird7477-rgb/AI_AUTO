# Browser Macro Verify Patterns

Use these patterns when replacing the generated `scripts/verify.sh` placeholder
in a browser macro project. Pick the smallest set that proves the requested
workflow; do not copy commands that the project cannot actually run.

## JavaScript Syntax Checks

Example shape:

```bash
for path in manifest.json service-worker.js content-script.js page-world-bridge.js; do
  [ -f "$path" ] || continue
  case "$path" in
    *.js)
      node --check "$path"
      ;;
    *.json)
      node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$path"
      ;;
  esac
done
```

For multi-file projects, prefer the project's existing package scripts:

```bash
npm test
npm run lint
npm run build
```

Do not add new Node dependencies during onboarding unless the user explicitly
requests it.

## Manifest And Permission Checks

Example checks:

```bash
node - <<'JS'
const fs = require('fs');
const manifest = JSON.parse(fs.readFileSync('manifest.json', 'utf8'));
if (manifest.manifest_version !== 3) {
  throw new Error('expected Manifest V3');
}
const permissions = new Set(manifest.permissions || []);
for (const permission of permissions) {
  if (!['scripting', 'storage', 'tabs', 'activeTab'].includes(permission)) {
    console.warn(`[verify] review broad permission: ${permission}`);
  }
}
for (const host of manifest.host_permissions || []) {
  if (host === '<all_urls>' || host === '*://*/*') {
    throw new Error(`review overly broad host permission: ${host}`);
  }
  if (host.includes('*')) {
    console.warn(`[verify] review wildcard host permission: ${host}`);
  }
}
JS
```

When a change creates or closes tabs, verify that the manifest includes only the
permissions required by the specific operation and that asynchronous tab
creation is routed through the service worker rather than `window.open()`.

## Bridge Boundary Checks

For projects that need page-owned globals, add static checks that confirm a
MAIN-world bridge exists and content scripts do not read page globals directly.
Example shape:

```bash
grep -R "world.*MAIN\\|\"world\": \"MAIN\"" manifest.json .
grep -R "__.*_request\\|CustomEvent" .
```

Adapt these checks to the project's real bridge names. Static grep is fallback
evidence; runtime smoke is stronger.

## Runtime Smoke Checks

Prefer Playwright or a project-owned browser smoke when available:

```bash
npm run smoke
```

The smoke should prove the smallest safe workflow:

- extension or macro loads
- target page is detected
- expected selector is found
- bridge or message path responds
- one non-destructive action updates the page's real source of truth
- timeout and failure paths do not leave intervals, observers, or tabs running

Do not run smoke checks against production data unless the project explicitly
defines the safe account, safe record, allowed action, and rollback evidence.

## User-Visible Chrome / CDP Checks

Use `docs/CHROME_CDP_ACCESS.md` as the single source of truth for Chrome remote
debugging safety, loopback binding, profile isolation, and evidence reporting.
For vendor UI and extension behavior, prefer a user-visible Chrome session over
background/headless automation when confirming real phenomena. Example shape:

```bash
# Example only. Prefer a project-owned wrapper so sandbox approvals and flags are stable.
google-chrome \
  --remote-debugging-port="${CHROME_DEBUG_PORT:-9222}" \
  --user-data-dir="${CHROME_DEBUG_PROFILE_DIR:?set a disposable/debug profile dir}"
```

Then attach Playwright or another inspector to the existing browser over CDP and
report the evidence required by `docs/CHROME_CDP_ACCESS.md`.

Headless Playwright is acceptable for repeatable project-owned smoke checks, but
it is fallback evidence for vendor UI behavior that depends on popups, focus,
extension permissions, user login state, or visible browser interaction.

## Ecount Checks

For Ecount ERP projects, project-specific verification should check the relevant
subset of:

- service worker tab creation uses `chrome.tabs.create({ active: false })`
- async message handlers return `true`
- Ecount globals are accessed through the MAIN-world bridge
- grid updates call `setCell()` or the confirmed internal model API
- `data-columnid` is used where Ecount column IDs are read
- grid key diagnostics report available keys without logging business data

Runtime smoke should use a safe Ecount test company or sandbox-like workflow
when available. If only static verification is possible, report it as fallback
evidence.

## Verification Script Guardrails

- Fail fast on missing required environment variables for browser smoke tests.
- Print the target browser, extension surface, and smoke environment before
  running runtime checks.
- Never require private credentials in the repository.
- Never dump full page HTML, cookies, localStorage, screenshots with sensitive
  data, or business records into committed artifacts.
- Clearly report skipped runtime checks and why they were unavailable.
