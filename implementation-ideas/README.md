# Implementation ideas

Authoring-only notes for `lizard-agent-layer`. Not product code, operator docs, or a release contract.

Same-topic sources merge in place. Product edits still need an explicit Go (e.g. “0005 residual umsetzen”).

**Final review (2026-09-10)** against tree **v1.5.1** (`HEAD` 4 commits after tag). Independent audit: overlay calorie + composite tests PASS on Windows PowerShell 5.1; `check-repository-drift` PASS; no `pwsh` on the audit host; full `ci.ps1` not run.

| ID | Title | Status | Remaining work |
| --- | --- | --- | --- |
| [0001](0001-front-door-install-contract.md) | Front-door install: harness + plans outside target | **Shipped** (wp14) | Public plan paths outside target; calorie test widened |
| [0002](0002-human-plan-approval.md) | Human plan card; digest/signed opt-in | **Shipped** 1.5.0 (ADR 0024) | None blocking. Keep as history. |
| [0003](0003-premortem-matching-honesty.md) | Premortem L/M/H + USING | **Shipped** 1.5.0 | Named `premortem` install path is 0006 residual |
| [0004](0004-apply-command-option-binding.md) | Markdown Apply must echo bound CLI | **Shipped** (wp14) | Apply snippets echo bound flags; `-AllowTargetReportWrite` generated + tested |
| [0005](0005-windows-operator-happy-path.md) | Wrappers, `layer_root`, risk-tiered doctor | **Shipped** (wp14) | Wrappers shipped in 1.5.0; `prompt-trust.md` aligned with adapter skip in wp14 |
| [0006](0006-implementation-skill-and-matching-budget.md) | Composite `implementation` + matching budget | **Shipped** (wp15) | Composite skill, description diet, 4-skill docs, FAIL-twice stop, Findings vs Human callouts |
| [0007](0007-portable-execution-tiers.md) | Fast vs rigorous; no Codex `.agents/rules/` | **Shipped** (wp15) | USING shipped; adapter Output residual diet; Stop rules; Cursor MDC docs |
| [0008](0008-measurable-loop-control.md) | Optional loop `control` + dampener | **Later** | After 0006/0007 residuals. Pack only. |
| [0009](0009-instruction-debt-audit.md) | Optional instruction-debt paper audit | **Keep** | Paper audit for champions. Not always-on. |
| [0010](0010-correction-routing-not-company-brain.md) | Harvest `bucket`; reject HQ | **Keep** | Harvest routing into DECISIONS/LESSONS/PREFERENCES. No company-brain OS. |
| [0011](0011-post-151-contract-hygiene.md) | Stale claims after 1.5.1 | **Shipped** (wp14) | Drift baseline 1.5.1, validate allowlist, visual-architecture RS256/26 packages |

## Recommended remaining Go order

1. **0006 residual** — description diet + README/profiles/architecture/examples; named `premortem` / `repo-grounded-change` honesty; `implementation` Stop on two identical FAILs; Findings vs Human callouts.
2. **0007 residual** — adapter Output/Pause/Evidence; Cursor always-on honesty.
3. **0010** — harvest routing.
4. **0009** — if a champion wants the paper audit.
5. **0008** — only if the next product goal is recurring loops.

Do **not** reopen as new ideas: Graphify/Graft, Ruflo/Claude-Flow, OpenViking, context-mode, Spec Kit, HQ/company-brain, Ponytail plugin, Anshu Luna+Astra routing, Abdo Astra Plus-quota / “max 10 tests”, wait-what / CONTEXT.md / STE100, pi-review / `/review`. Reject tables in 0006/0007/0008/0009 already hold those.

## Package cut (for a separate implementer)

IDs stay. Do not renumber. History stays in the file **below** the Remaining WP box.

| Cut | Honest? | Note |
| --- | --- | --- |
| 0001 vs 0004 | **Two IDs, one session** | Same Markdown files (`INSTALL.md`, getting-started). 0001 = plan *paths*; 0004 = Apply *flags*. Pick up together; do not ship 0001 without 0004. |
| 0002 / 0003 | Yes | Shipped. Closed. Do not reopen. |
| 0005 | Title is stale | Remaining work is **prompt-trust**, not Windows wrappers. npm.cmd / doctor JSON are P2 riders. |
| 0006 | One theme, four file-sets | (a) skill `description:` (b) README/profiles/examples (c) named `premortem` honesty (d) `implementation` SKILL.md body: FAIL-twice Stop **and** Findings vs Human callouts. One Go may do all four; they do not need new IDs. |
| 0007 | Remaining WP is small | Adapter Output/Pause/Evidence + Cursor doc. The reject tables are **not** work; do not implement Graphify/Ruflo from this file. |
| 0008 / 0009 / 0010 | Yes | Optional, later, distinct objects. |
| 0011 | Yes, keep tiny | Counts/baselines/parse list only. Six-skill README is 0006, not 0011. |

**Status words:** Shipped = closed. Residual = open product WP. Later = after residuals. Keep = optional, not in the daily-overlay queue. New = 0011 only.

A Go must name the ID and mean the **Remaining WP** box, not the historical Problem section.
