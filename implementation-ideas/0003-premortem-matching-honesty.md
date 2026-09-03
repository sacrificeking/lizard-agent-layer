# 0003 — Premortem matching honesty (minimal)

**Work package:** one small edit set if [0006](0006-implementation-skill-and-matching-budget.md) is **not** done first. If 0006 lands, do only the premortem L/M/H labels and the USING one-liner; drop the staged-execution “one of two skills” sentence (the composite skill replaces it).
**Source:** existing `skills/premortem/` plus Casaus thread (already absorbed). Keepable leftover: likelihood×impact labels; human trigger; 2-skill-cap honesty.
**Do not** copy the viral 6-month narrative skill.

Do not change product files until this idea is explicitly approved for implementation.

## Problem

Premortem is in the `standard` / `enterprise-fullstack` six-skill list and `staged-execution` says “run premortem for medium/high-risk plans”. Daily effect is weak:

1. Adapters load **at most two** matching skills. A normal implementation pass takes `staged-execution` + `repo-grounded-change`. Premortem is not loaded unless the user names it or it wins a matching slot.
2. `templates/operator-card.md` (installed `USING.md`) never mentions premortem, so humans do not ask for it.
3. Output ranks “most likely” vs “most dangerous” but does not label each listed mode with likelihood and impact, so the ranking is opaque.

Runtime enforcement of a third skill is an intentional non-goal (`docs/architecture.md`). This idea only makes the contract **honest** and the output **sortable**.

**Live install (degen-resource-hub):** Codex `AGENTS.md` allowed two skills; staged-execution implied more (`repo-grounded-change`, `premortem`, plus pack skills). 15 skills were installed, two could load. That is the 2-skill diet working as designed **and** the staged-execution contradiction this WP fixes. Do **not** raise the cap, do **not** always-load six skills, do **not** treat pack catalog size as a load quota.

## Solution

Three edits, calorie-neutral for always-on context:

| File | Change |
| --- | --- |
| `skills/premortem/SKILL.md` | On each concrete failure mode, require `likelihood: L\|M\|H` and `impact: L\|M\|H`. Keep synthesis-first output. Most Likely = highest likelihood; Most Dangerous = highest impact (state that). No 1–5 scales, no extra sections. |
| `templates/operator-card.md` | One bullet under daily prompts or review: before medium/high-risk edits (migrations, auth, CI, dependencies, large refactors), tell the assistant to run premortem. |
| `skills/staged-execution/SKILL.md` | Replace “run `premortem` for medium/high-risk plans” with: for medium/high-risk, **load `premortem` as one of the two matching skills** (instead of a second implementation skill) **or** stop and ask the user to name `premortem`. Do not claim a third skill will be loaded. |

Do not:

- Put premortem in adapters (breaks the 80-line budget).
- Add `evidence.json` or a new test suite for model behavior.
- Add it to `minimal`.
- Run premortem from `install.ps1`.
- Import Casaus’ Spanish skill or a probability×impact table dump.

## Implementation

1. `skills/premortem/SKILL.md`
   - Success criterion: every path-bound (or `gap:`) failure mode includes likelihood and impact as `L`, `M`, or `H`.
   - Output: keep the five synthesis bullets; add one line that those two rankings are derived from the L/M/H labels, not from new prose.
   - Stop conditions: keep “high-likelihood, high-damage”; map that to likelihood `H` **and** impact `H`.
2. `templates/operator-card.md` — one short bullet in §1 or §3. Ask-only `USING.md` stays ask-only in adapters (no adapter change).
3. `skills/staged-execution/SKILL.md` — Strategy bullet only, as above.
4. `tests/unit/overlay-calorie-budget.tests.ps1` — already checks adapter budget and six-skill list; should still pass with no adapter edits. Optional: assert operator-card contains `premortem` and staged-execution contains `two matching skills` / equivalent honesty phrase so the contradiction cannot return.
5. Changelog: one line under Changed, not a new feature headline.

Bump `skills/premortem/skill.json` `version` patch (e.g. `1.0.0` → `1.0.1`) if the package contract tracks SKILL.md edits; follow existing skill-package practice.

## Premortem

- Long L/M/H tables recreate the viral skill’s calorie. Cap: labels on the modes you already list, then the same five synthesis bullets.
- “Ask the user to name premortem” can nag on every bugfix. Keep the existing skip: trivial typos, local fixes, read-only.
- Operator-card growth is read by humans, not always-on tokens — still keep it one bullet.
- Honesty text does not make the host load a third file. If someone wants enforcement, that is a harness OS, not this WP.

## Done when

- Premortem output can be sorted by L/M/H without new sections.
- A human reading `.agent/USING.md` knows to demand premortem on risky work.
- `staged-execution` no longer implies a third matching skill.
- Adapter always-on line count unchanged.
- No product edit until explicit implement request.
