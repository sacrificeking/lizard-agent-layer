# Dependency And Toolchain Snapshot

Snapshot date: 2026-07-12. This is a release-readiness record, not an automated update policy for target projects.

`lizard-agent-layer` has no runtime package dependency, application framework, telemetry SDK, database driver, cloud SDK, or production service. PowerShell and Git run the repository tooling. Node.js and the npm development packages are required only for executable JSON Schema validation and repository CI.

## Direct Dependencies And Tools

| Component | Release Baseline | Latest Stable At Review | Purpose | Update Method |
| --- | --- | --- | --- | --- |
| Node.js | `>=22`; CI uses `24.18.0` LTS | `24.18.0` LTS; `26.3.1` Current | Runs schema validation and npm | Install a supported LTS release, then run `npm ci` and full CI |
| npm | Bundled with Node.js; review host used `11.9.0` | `12.0.1` | Reproduces the development dependency tree | Prefer the npm bundled with the selected Node LTS; if upgraded separately, regenerate the lockfile and run full CI |
| Ajv | `8.20.0` | `8.20.0` | Draft 2020-12 JSON Schema validation | `npm install --save-dev ajv@8.20.0` |
| ajv-formats | `3.0.1` | `3.0.1` | Date, date-time, URI, and related schema formats | `npm install --save-dev ajv-formats@3.0.1` |
| PowerShell | PowerShell 7 recommended; Windows PowerShell 5.1 compatibility | `7.6.2` stable | Portable scripts, tests, and local CI | Install the current stable PowerShell 7 release and run the four-host workflow |
| Git | `2.31+` recommended; review host used `2.52.0.windows.1` | `2.55.0` | Status, diff, worktrees, evidence binding, and release operations | Upgrade through the official Git distribution, then run worktree and verifier tests |
| `actions/checkout` | `v6.0.2`, pinned to `de0fac2e4500dabe0009e67214ff5f5447ce83dd` | `v6.0.2` | CI checkout | Verify the upstream release SHA, replace both workflow pins, and run GitHub CI |
| `actions/setup-node` | `v6.4.0`, pinned to `48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e` | `v6.4.0` | CI Node installation | Verify the upstream release SHA, replace both workflow pins, and run GitHub CI |

Use LTS Node.js for release and enterprise work. Current, odd, EOL, nightly, preview, and release-candidate runtimes are not release baselines even when local checks happen to pass.

## Locked Transitive Packages

| Package | Locked Version | License | Directly Managed |
| --- | ---: | --- | --- |
| fast-deep-equal | `3.1.3` | MIT | No; resolved by Ajv |
| fast-uri | `3.1.3` | BSD-3-Clause | No; resolved by Ajv |
| json-schema-traverse | `1.0.0` | MIT | No; resolved by Ajv |
| require-from-string | `2.0.2` | MIT | No; resolved by ajv-formats |

Every locked npm package has an integrity hash in `package-lock.json`. Update transitive packages through their direct parent unless a security fix requires an explicit override.

## One-Time Release Verification

Run from the source repository:

```powershell
npm outdated
npm audit
npm ci --ignore-scripts
npm run schema:check
pwsh -NoProfile -File .\scripts\ci.ps1
```

Review upstream release notes before changing a major version. For GitHub Actions, pin the verified full commit SHA associated with the intended release instead of a mutable major tag.

## Audit Result

- Direct npm packages were already current at review time.
- Direct and transitive package licenses are permissive: MIT or BSD-3-Clause.
- No install scripts are required by the dependency tree.
- No package is used in installed target projects; target installation copies repository artifacts and does not run npm.
- A live registry check on 2026-07-12 reported no outdated packages.
- `npm audit` reported zero known vulnerabilities: 0 info, low, moderate, high, or critical findings.
