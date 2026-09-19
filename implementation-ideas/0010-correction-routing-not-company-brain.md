# 0010 — Route corrections into existing memory files (not a company brain)

**Work package:** small harvest + USING edits. No new always-on file. No new OS.
**Source:** VibeMarketer_ “company brain” / HQ thread (X 2092243372929151135, https://x.com/VibeMarketer_/status/2092243372929151135). Distill the routing table; do not absorb HQ or the marketing folder taxonomy.
**Related:** `skills/project-decision-harvest`; `templates/memory/semantic/{DECISIONS,LESSONS}.md`; `PREFERENCES.md`; `protocols/permissions.md`; `skills-local`; [0006](0006-implementation-skill-and-matching-budget.md) matching; [0009](0009-instruction-debt-audit.md) apply-nothing.

**Status (2026-09-19):** **Shipped** (wp16). Harvest skill classifies learnings into `decision`, `lesson`, `preference`, `local-skill`, `permissions-gate`, or `nowhere`. Operator card provides correction routing guidance. Reject SaaS company-brain layer.

## Verdict

**Take the routing table. Reject the product.**

The thread is a pitch for [HQ](https://www.hqforwork.com): one SaaS “company brain” across Claude, Cursor, and Codex, with `company-brief` / `people` / `projects` / `workers` / `learnings` and a paste-prompt that generates the tree. That is a **competing context layer**, not a lizard pack.

The overlay already is the portable “one home” (`\.agent/` + sidecar adapters). Memory, judgment, capability, and gates already exist as **separate files**. The real gap is narrower: `project-decision-harvest` only proposes `DECISIONS.md`, so corrections, quirks, tastes, and safety all collapse into one junk drawer — or into a new skill.

## What the thread got right

- Private chats trap corrections; the next agent starts from scratch.
- A **map**, then pull detail by need — not the whole company in every prompt.
- Corrections are often more valuable than the fixed sentence.
- Route the fix to the layer that should remember it; **review before it becomes shared**.
- Never promote a guess to company knowledge.
- When sources conflict, follow an explicit order.
- Start with one workflow; leave empty what you cannot maintain.

## Map onto files we already ship (do not add HQ folders)

| Thread bucket | Overlay destination | Who may write |
| --- | --- | --- |
| Missing/outdated fact, architecture choice | `memory/semantic/DECISIONS.md` | harvest proposal → human line-by-line |
| Recurring repo quirk / failed approach | `memory/semantic/LESSONS.md` | same review; not a decision |
| Personal style (commit voice, explanation depth) | `memory/personal/PREFERENCES.md` | operator; not team policy |
| Repeatable coding technique for *this* repo | `.agent/skills-local/<name>/` committed | target-owned; not a layer catalog skill |
| Repeatable job with cadence | existing **loop** in `loop-engineering` pack | not a `workers/` tree |
| Dangerous action | `protocols/permissions.md` never-allowed / paste-stop | **layer plan only**; harvest must not widen or copy gates into Markdown memory |
| Stale task state | `memory/working/WORKSPACE.md` | handoff protocol; ephemeral |
| Overlay instruction that fights itself | [0009](0009-instruction-debt-audit.md) paper audit | apply nothing |

Source order is already `prompt-trust.md`. The front door is already ask-only `USING.md` + `project-context.md` (“read DECISIONS/LESSONS **when relevant**”). Do not add `company-map.md` as always-on.

## What not to absorb

| Thread choice | Why it stays out |
| --- | --- |
| HQ as the shared home | Overlay *is* the portable home. A third vendor context layer splits the brain again. |
| `company-brief.md`, `priorities.md`, `people/`, `projects/` | Org wiki. Target README / issue tracker / `DECISIONS.md`. Not an installable pack (same reason as no ING pack). |
| `workers/` as a new skill class | Loops already exist. A worker OS is HumanLayer-adjacent. |
| Paste-prompt that generates the whole tree | Creates empty always-on files the model then treats as policy. 0007 required-reading stack. |
| “By Wednesday the whole company has Tuesday’s lesson” | Auto-share without review. Harvest already **stops** for confirmation. ADR 0008 spirit. |
| Marketing workflow as the first overlay skill | Domain pack. Catalog slogan skills stay opt-in; do not add a vibe-marketer skill. |
| Copying Claude/Cursor/Codex trees into `~/.codex` | Graft-shaped; 0009 already forbids mutating user-global config. |
| OpenViking session commit → LLM extract → auto write profile/preferences/events/soul | Same auto-share failure. Overlay harvest **proposes** 3–5 path-cited rows and stops. Do not add `soul.md`/`identity.md` (personality always-on). Do not add `entities/`/`cases/`/`trajectories/` trees. L0/L1/L2 as extra files per skill is 0006 progressive disclosure, not a third Markdown sibling. |
| `CONTEXT.md` / `CONTEXT-MAP.md` (wait-what ubiquitous language) | Second glossary. Overlay nouns already live in `DECISIONS.md` (plus LESSONS/PREFERENCES). Do not install a parallel map. Re-pitch slash skill stays out ([0007](0007-portable-execution-tiers.md)). |

## Solution

Keep harvest small. Teach it to **classify** before it proposes a DECISIONS write.

1. `skills/project-decision-harvest/SKILL.md` (and `implementation` pointer if 0006 lands first): after inspecting the repo or a human correction, emit each item with `bucket`: `decision` | `lesson` | `preference` | `local-skill` | `permissions-gate` | `nowhere`.
2. Default still 3–5 items, path-cited or `unverified`. `nowhere` = do not write (one-off fix, guess, secret, stale). `permissions-gate` = cite the existing `permissions.md` line; **do not draft a new never-allowed** in the harvest output (that is a layer change, separate plan).
3. `local-skill` = propose a **target** `.agent/skills-local/` stub (When / Stop only), never a new `skills/<catalog>/` entry.
4. `templates/operator-card.md` one bullet: if you corrected the agent, say whether that belongs in DECISIONS, LESSONS, PREFERENCES, skills-local, or nowhere — do not only fix the sentence. Optional same-file rider (**not** this WP’s definition of done): if you did not follow the last answer, say so and ask it to re-state the files it will change, using DECISIONS nouns, including the missing premise — not “be shorter.” Do not install `wait-what`.
5. No new protocol. No `learnings.md`. No installer folder `people/` / `workers/`. Always-on calorie unchanged.

## Implementation

1. Harvest Output: add `bucket` + destination path; Stop still “proposal only, no write.”
2. USING one line under daily prompts or review — not a new chapter.
3. Optional: `docs/skill-authoring.md` one sentence that harvested techniques go to `skills-local`, not the layer catalog.
4. Tests: harvest fixture that a “prefer conventional commits” item is `preference`, a “migrations need premortem” item is `decision` or `nowhere` (already in implementation/premortem — do not duplicate into DECISIONS), a “never paste prod dumps” item is `permissions-gate` with no proposed memory write.

## Premortem

- Routing without review recreates HQ auto-share. Mitigate: still stop; human confirms each row.
- `LESSONS.md` becoming always-on if adapters start “read all memory every turn.” Keep project-context **when relevant** (0007).
- `local-skill` proposals exploding the target skill list. Cap: at most one local-skill stub per harvest; description must be narrow (0006 diet).
- Classifying a paste-stop reminder as `decision` duplicates `permissions.md` into memory (instruction debt). `permissions-gate` writes **nothing**.
- Building the HQ tree “because the tweet said start small” still adds eight empty files. Empty files become policy (Astra skill sensitivity). Do not create them.

## Done when

- Harvest can send a correction to DECISIONS, LESSONS, PREFERENCES, skills-local, permissions-cite, or nowhere — and still applies nothing until the human confirms.
- Layer does not ship HQ, workers, people, company-brief, or a marketing pack.
- Adapters do not gain a required-reading map.
- 0006/0009 remain the matching and overlay-audit WPs; this does not replace them.
