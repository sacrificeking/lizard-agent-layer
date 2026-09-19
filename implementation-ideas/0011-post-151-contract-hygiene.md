# 0011 — Post-1.5.1 contract hygiene

**Status (2026-09-16):** **Shipped** (wp14). Drift baseline bumped to 1.5.1, `docs/visual-architecture.md` claims RS256 and 26 packages, `scripts/validate.ps1` parse allowlist includes all 1.5.x scripts and unit tests.

## Shipped

- `registry/drift-baseline.json` bumped and verified with `drift-check.ps1 -Strict`.
- `docs/visual-architecture.md` specifies RS256 cryptographic signatures and 26 reusable packages.
- `scripts/validate.ps1` validates `lizard.ps1`, `new-approval.ps1`, `loop-run.ps1`, `loop-recover.ps1`, `publish-release.ps1`, and all 1.5.x unit tests.
- Change declaration `changes/wp14-prompt-trust-and-front-door-residuals.json` satisfies `contract-check.ps1 -Strict`.

1. `registry/drift-baseline.json` `"layer_version": "1.5.0"` while `VERSION` is `1.5.1` (and HEAD is already past the tag).
2. `docs/visual-architecture.md`: “Ed25519” (product is **RS256**) and “22 reusable packages” (catalog is ~26 skill packages).
3. `scripts/validate.ps1` parse allowlist omits `scripts/lizard.ps1`, `new-approval.ps1`, `loop-run.ps1`, `loop-recover.ps1`, `publish-release.ps1`, and newer unit tests (`overlay-calorie-budget`, `composite-implementation-skill`, `windows-happy-path`, `human-plan-approval`). Focused CI still runs those tests; validate will not catch a parse break in the new front door.
4. `changes/release-v1-5-1-and-ci-hygiene.json` does not list adapter/profile/doc paths that 1.5.0 actually changed — optional, only if a contract-check requires it.

Out of scope here (owned elsewhere):

| Claim | Owner |
| --- | --- |
| README / `docs/profiles.md` “six core skills”; `docs/architecture.md` “at most two matching skills”; `examples/*.agent-layer.json` | [0006](0006-implementation-skill-and-matching-budget.md) |
| `.\.tmp` plan paths; harness snippets | [0001](0001-front-door-install-contract.md) |
| INSTALL Apply omitting `-MemoryMode` | [0004](0004-apply-command-option-binding.md) |
| `prompt-trust.md` vs adapter doctor skip | [0005](0005-windows-operator-happy-path.md) |
| Cursor `alwaysApply: false` vs getting-started | [0007](0007-portable-execution-tiers.md) |

## Implementation

1. Bump drift-baseline `layer_version` to the current `VERSION` (regenerate via the existing drift script if that is the supported path).
2. visual-architecture: RS256; skill-package count from the catalog (or drop the number).
3. `validate.ps1`: add the missing scripts and the new focused tests to the parse allowlist.
4. No new protocol. No calorie change.

## Premortem

- Regenerating drift-baseline without reviewing the diff can hide real drift. Prefer the existing `check-repository-drift` / `drift-check` path.
- Putting six-skill README fixes here duplicates 0006. Leave them there.
- Counting skills by directory vs `skill.json` `lifecycle_state: active` can disagree. Use active packages only.

## Done when

- Drift baseline version matches `VERSION`.
- visual-architecture does not claim Ed25519 or a stale package count.
- `validate.ps1` parses `lizard.ps1`, `new-approval.ps1`, and the 1.5.x unit tests.
- 0001/0004/0005/0006/0007 remain the behavior WPs.
