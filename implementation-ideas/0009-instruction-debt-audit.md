# 0009 — Instruction-debt audit (optional)

**Work package:** one named, on-demand procedure. Not always-on. Not a new OS.
**Source:** Av1dlive “instruction debt audit” Codex prompt (X 2096578191691518314). Distill; do not paste the full prompt into adapters.
**Also:** GPT-6 Astra official prompting (https://developers.openai.com/api/docs/guides/latest-model?model=gpt-6-astra) — “strongly recommend auditing skills and other files accessible to your model … such as `AGENTS.md`.” Confirms this idea; does not widen it. Runtime “cite the blocking skill” lives in [0007](0007-portable-execution-tiers.md), not here.
**Also:** OpenAI “Rethinking skills and prompts for GPT-6 Astra” (https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra) — vendor version of this audit (descriptions, required-reading stacks, leftover ask-first). Description **rewrites** in the layer catalog are [0006](0006-implementation-skill-and-matching-budget.md). This skill still only paper-walks a live target.
**Related:** [0007](0007-portable-execution-tiers.md) is *when* heavy path runs; this is *how* a champion finds contradictory standing instructions in a **live target**. Overlay calorie CI already gates the **layer source**.
**Status (2026-09-10):** **Keep, not started.** Optional, named, apply-nothing. The 1.5.1 audit is exactly the class of walkthrough this skill would produce (`prompt-trust` vs adapter skip; Cursor `alwaysApply`; six-skill docs vs four-name diet). Do **not** make it always-on or a sixth core skill. Do not wait for 0009 to fix those — 0005/0006/0007 residuals already own the product diffs.

Do not change product files until this idea is explicitly approved for implementation.

## Verdict

**Learn the procedure. Do not absorb the tweet as overlay.**

The prompt is a preview-first audit of agent instructions: map always-on vs discovery vs on-demand, inspect skill triggers / skill bodies / AGENTS.md / permissions / completion, paper-walk five scenarios, propose exact diffs, **apply nothing**. That is lizard-shaped (prompt-trust, sidecar, calorie, 0007 tiers).

It is **not** a massive new product. It would have caught the degen-resource-hub contradictions (2-skill adapter vs staged-execution wanting four names; doctor-every-turn; SHA parrot) **without** inventing Graft, HumanLayer, or a skill catalog.

`research-audit` is the wrong home: that skill is third-party/source evaluation, not overlay self-audit.

## What already exists

| Layer | What it covers | What it misses |
| --- | --- | --- |
| `tests/unit/overlay-calorie-budget.tests.ps1` | Source adapters ≤80 lines, USING ask-only, diet skill list | Target sidecars, `skills-local`, hooks, host global `~/.codex` |
| `doctor.ps1` / `manifest-diff.ps1` | Hash/ownership integrity | Whether instructions **fight each other** |
| `protocols/prompt-trust.md` | Precedence | No walkthrough of a typo vs a migration |
| 0007 | Fast vs rigorous *policy* | No champion checklist to find debt in the installed tree |

## Keepable (small)

1. **Five paper walkthroughs** (do not execute): typo; DB migration; UI change that needs visual check; failing local test; deployment needing approval. Trace: request → activated files → required reading → actions → approval → stop. Label guesses as hypotheses.
2. **Three instruction classes:** always-on, skill *description* (discovery), skill *body* (on demand). Flag descriptions that fire on unrelated tasks (OpenAI: Codex truncates long descriptions; topic dumps like “use when working with databases / UI / analyze” steal the load). Extra paper walk: a typo or one-line UI change must **not** activate `backend-api`, `design-system`, `research-audit`, or a required-reading stack.
3. **Audit first, apply nothing.** Findings as proposed diffs with disposition: keep / shorten / split / narrow trigger / clarify boundary / investigate removal. Preserve the useful constraint.
4. **Do not auto-broaden permissions.** Do not delete a safeguard because the model is newer. The blog’s “Astra has better judgment, soften ask-first” is a **target-local** conversation after the walkthrough, never an audit fix that widens `permissions.md`.
5. **Coverage inventory:** list uninspected files; never claim a complete map. If the target also has Spec Kit (`.specify/`, `/speckit.*`), **context-mode** (`ctx_*`), **OpenViking** (`viking://`, `soul.md`), **Ruflo/Claude-Flow** (`npx ruflo`, `.claude-flow/`), **Graphify** (`graphify-out/`, `$graphify` / `/graphify`, always-on GRAPH_REPORT.md), **wait-what** / `CONTEXT.md`, or **pi-review** (`.pi/` + `REVIEW_GUIDELINES.md`, `/review`, `/end-review`, `/diff-review`), list them as a **second overlay**. Do not fold those trees into lizard adapters. Flag fights with `permissions.md` / Tier 1, Evidence, harvest, inherit-current, and required-reading (wiki/graph before every architecture answer). Apply nothing to those files from this audit.

## What not to do

- Paste the long prompt into `AGENTS.md` or adapters (calorie, always-on debt).
- Make the audit a default pack skill or sixth core skill.
- Quantify “tokens saved” without measurement.
- Treat the audit output as authority to `-Apply` overlay edits (still plan + human).
- Scan `~/.codex` or other **user-global** config from install scripts (report-only if the *human* asks; do not mutate machine-wide Graft-style).
- Absorb Spec Kit, `specify-cli`, or a `/speckit.*` command pack (already a non-goal; architecture: SDD CLIs are adjacent).

## Solution

Optional, named, on-demand:

- Prefer **`templates/operator-card.md`**: short “If the overlay feels heavy or contradictory, ask for an instruction-debt audit (read-only).” Plus a **`templates/` or `skills/instruction-debt-audit/`** contract-shaped SKILL.md (When / Success / Boundaries / five walkthroughs / Output / Stop). Not in `standard` defaults.
- Champions invoke it by name. Adapters already allow “unless the user explicitly names a skill.”
- Layer **source** maintainers can run the same skill against this repo; CI stays calorie tests, not an LLM audit.

If a skill file is too much: USING.md + `docs/troubleshooting.md` section only. Skill is better because descriptions are the first failure mode the prompt targets.

## Implementation

1. `skills/instruction-debt-audit/SKILL.md` + `skill.json` — lean; five walkthroughs as required output; Stop = deliver audit, do not edit.
2. Do **not** add it to `profiles/standard.json` / `enterprise-fullstack.json`.
3. `templates/operator-card.md` — one bullet.
4. Overlay calorie tests unchanged (skill is not always-on). Optional: assert the skill is absent from default profile lists.
5. Changelog: Added optional skill, not a platform feature.

## Premortem

- An LLM audit will invent cleanup. Mitigate: “If already well scoped, say so. Do not invent work.”
- Walking “deployment” may tempt the model to read secrets/CI. Mitigate: paper only; no network; no `.env`.
- Putting the full tweet prompt in USING.md makes USING longer than the overlay. Distill.
- Running this as auto-doctor every session recreates item 10 of the degen feedback. Named only.

## Done when

- A champion can name the audit and get a read-only report with the five walkthroughs and proposed diffs.
- Default overlay load path does not include it.
- Permissions cannot be widened as an “audit fix” without a separate human plan.
- 0007 remains the standing two-tier contract; this does not replace it.
