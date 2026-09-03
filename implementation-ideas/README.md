# Implementation ideas

Authoring-only notes for `lizard-agent-layer`. Do not treat these files as product code, operator docs, or a release contract.

Ideas that belong in the product stay here until an explicit implementation request. Same-topic sources merge in place.

| ID | Title | Work package |
| --- | --- | --- |
| [0001](0001-front-door-install-contract.md) | Front-door install contract: harness flags and plan paths outside the target | WP-A docs + tests. Former WP-B (mandatory signed apply) superseded by 0002 |
| [0002](0002-human-plan-approval.md) | Human-readable plan approval; `new-approval.ps1`; signed **only** for destructive layer mutations | WP-1 card; WP-2 opt-in digest; WP-3 kit + destructive-only RSA |
| [0003](0003-premortem-matching-honesty.md) | Premortem L/M/H + USING one-liner; staged-execution honesty if 0006 not first | Small skill/card edits |
| [0004](0004-apply-command-option-binding.md) | Generated Apply command omits bound options (`PLAN_BINDING_OPTIONS_MISMATCH`) | P0 installer + test that uses the Markdown Apply block |
| [0005](0005-windows-operator-happy-path.md) | Windows wrappers, npm.cmd, manifest `layer_root`, risk-tiered doctor | Docs + `lizard.ps1`/`lizard.cmd` + doctor flag; no scripts in target |
| [0006](0006-implementation-skill-and-matching-budget.md) | Composite `implementation` skill; matching budget instead of rigid two | One skill + four-name diet + adapter prose |
