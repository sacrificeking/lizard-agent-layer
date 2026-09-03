# 0006 — Composite `implementation` skill and matching-skill budget

**Work package:** one new composite skill + profile diet + adapter wording. Does not raise a runtime cap. Does not absorb catalog slogan skills.
**Live evidence:** Codex `AGENTS.md` allowed two skills; staged-execution implied grounding + premortem; packs added more installed trees. Installed count ≠ load quota. The rigid “at most two” line fights the workflow it documents.
**Related:** [0003](0003-premortem-matching-honesty.md) (L/M/H + USING). Prefer this WP for the load-unit problem; keep 0003 for labels.

Do not change product files until this idea is explicitly approved for implementation.

## Problem

Adapters: “Load at most two matching skills … unless the user explicitly names a skill.”

`staged-execution` then says: ground with `repo-grounded-change`, run `premortem` on medium/high-risk. A dry-run also wanted `research-audit` and pack skills. That is four-to-six **names** against a two-file cap.

Raising the cap to six is the wrong fix: it is still a fake runtime quota (Markdown cannot enforce it) and it blows matching calorie. Architecture already lists “runtime cap on a third skill file” as a non-goal.

The operator recommendation is right in spirit: **one composed implementation skill**, and replace the magic “two” with a **matching-skill budget** (prose, not a loader).

## Solution

### 1. Skill `implementation`

New `skills/implementation/SKILL.md` (plus `skill.json`) that is the default load unit for non-trivial code work. It **inlines by reference** the existing contracts, it does not duplicate three full skills:

- Strategy: current `staged-execution` 10-80-10, inherit-current, harvest if DECISIONS placeholder.
- Grounding + review packet: current `repo-grounded-change` (siblings, named repo tests, 3 diff-specific questions).
- Premortem: current `skills/premortem` **only** for medium/high-risk; skip trivial. After 0003, L/M/H labels live here or stay in `premortem` and this skill says “follow premortem output contract”.

Keep `staged-execution`, `repo-grounded-change`, and `premortem` as **named** skills for explicit user load and for `staged-execution` as a protocol-adjacent skill. Defaults should not list all three plus the composite.

`standard` / `enterprise-fullstack` default `skills` become:

```text
git-safety, implementation, research-audit, project-decision-harvest
```

Four names, one implementation load. Packs still add catalog skills; those stay opt-in specialists, not part of `implementation`.

`minimal` unchanged (`git-safety`, `research-audit`, `staged-execution` is acceptable, or `git-safety` + `implementation` if you want one diet everywhere — prefer leave `minimal` light, no premortem).

### 2. Matching-skill budget (adapter prose)

Replace “at most two matching skills” with:

- Load the **one** best match for the task (usually `implementation`).
- Add **at most one** extra matching skill if it is a specialist the user needs (named pack skill, `research-audit`, `premortem` if they asked for the standalone file).
- Combined matching SKILL.md bodies should stay small (suggest ≤120 lines as a **guidance** budget, not a CI line-count of the whole catalog).
- If the user **names** skills, those names win (existing exception).
- Do not claim the host will refuse a third file.

Always-on adapter + prompt-trust + permissions stays ≤80 lines. Matching skills are still on-demand.

This is **not** a context-graph engine, skill OS, or token compressor.

### 3. Risk-tiered use (with 0005)

Trivial work: do not load `implementation`’s premortem branch; git-safety + permissions suffice. Medium/high: `implementation` including premortem. Doctor still 0005 (unknown-trust only).

## Implementation

1. Add `skills/implementation/` contract-shaped SKILL.md: When to Use / Success Criteria / Boundaries / Evidence / Output / Stop. Point to sibling skill names instead of pasting three documents in full — keep the composite **shorter than the sum** (target ≤80 lines of SKILL.md).
2. `skill.json` like other core skills; `analyze-target.ps1` default skill lists; `profiles/standard.json` and `enterprise-fullstack.json`; overlay-calorie test currently asserts six named skills — change to the four-name diet and require `implementation` instead of the three separate defaults.
3. Six adapters: matching-budget wording; calorie test still ≤80 always-on.
4. `staged-execution` Strategy bullet: “default implementation path is the `implementation` skill; do not also load repo-grounded-change and premortem unless the user named them.”
5. Changelog + `changes/` declaration if profiles are contract-sensitive.

Do not:

- Fold `frontend-engineering`, `precision-domain`, `database-engineering` into `implementation`.
- Delete the three standalone skills.
- Add a runtime skill loader or “2 vs N” enforcer.

## Premortem

- A fat composite that pastes three SKILL.md files undoes the diet. Cap length; reference, don’t clone.
- Leaving all six defaults **plus** `implementation` makes matching worse. Replace, don’t append.
- “≤120 lines matching budget” in adapters can rot like “two skills”. Calorie CI measures always-on, not matching. Accept that, or add a cheap test that the `implementation` SKILL.md itself is ≤80 lines.
- inherit-current remains one model for plan/simulate/review. The composite does not create an independent verifier. That stays an L2/loop concern (feedback item 2 — not this WP).

## Done when

- Default standard install lists four core skills including `implementation`, not six overlapping ones.
- Adapters no longer say a hard “two” that contradicts the workflow.
- Pack slogan skills remain opt-in and outside the composite.
- Always-on calorie still ≤80.
