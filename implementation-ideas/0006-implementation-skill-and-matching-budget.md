# 0006 — Composite `implementation` skill and matching-skill budget

**Work package:** one new composite skill + profile diet + adapter wording. Does not raise a runtime cap. Does not absorb catalog slogan skills.
**Live evidence:** Codex `AGENTS.md` allowed two skills; staged-execution implied grounding + premortem; packs added more installed trees. Installed count ≠ load quota. The rigid “at most two” line fights the workflow it documents.
**Related:** [0003](0003-premortem-matching-honesty.md) (L/M/H + USING). [0007](0007-portable-execution-tiers.md) is the fast vs rigorous **when**; this WP is the **what** gets loaded.
**Also:** OpenAI “Rethinking skills and prompts for GPT-6 Astra” (https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra). Description diet + router body merge here; AGENTS.md required-reading and “Astra is aligned so drop gates” stay in [0007](0007-portable-execution-tiers.md) / [0009](0009-instruction-debt-audit.md). No new idea.
**Also:** Abdo GPT-6 Astra Plus-quota prompt (https://x.com/abdobuild/status/2098161708510429333, follow-up https://x.com/abdobuild/status/2098582463261856164). Quota % and “max 10 tests” stay out ([0007](0007-portable-execution-tiers.md) reject). One Stop line belongs in this skill body, not a new idea and not always-on adapters.
**Also:** Earendil `pi-review` (https://github.com/earendil-works/pi-review) — Pi `/review` extension, Codex-rubric port. Reject the host (table in [0007](0007-portable-execution-tiers.md)). Keepable Output split belongs in this skill body, not a fifth core skill.

**Status (2026-09-16):** **Shipped** (wp15). Composite skill, 4-name diet, adapter matching prose, calorie assert-4, description diet, public docs, FAIL-twice stop, and Review Packet (Findings vs Human callouts) shipped.

**Completed in wp15 (all four file-sets shipped):**

1. **Descriptions:** narrow `description:` so `implementation` is the only default “non-trivial implementation” match; `git-safety` = git **mutation**; `research-audit` not analyze/evaluate-everything; pack slogans not topic dumps (section 2b).
2. **Docs/examples:** README, `docs/profiles.md`, `docs/architecture.md`, `examples/*.agent-layer.json` say **four** core skills, not six; adapters “one best + at most one specialist”, not “at most two”. Drop phantom `install.ps1 -Skills`.
3. **Named standalones:** stock standard does not install `premortem` / `repo-grounded-change`. Either inline enough premortem in `implementation` for medium/high, or document the real lifecycle named-load path.
4. **Skill body** (`skills/implementation/SKILL.md`, same file):
   - **Stop on repeated FAIL:** If the same named verification command fails twice with an unchanged approach, stop and report the command + visible output. Do not invent extra tests, expand scope, or “work around” the failure. After two identical FAILs a different strategy is allowed **once**; a third FAIL on the new strategy still stops. Do not encode “10 tests”, Plus weekly %, or `gpt-6-astra`. `minimal-fix` already has “fails twice”; default daily Astra/Codex load is this skill, not the L2 pack. Adapter Evidence ([0007](0007-portable-execution-tiers.md)) stays PASS-side (no extra tests, no repeat after PASS).
   - **Review packet:** keep Pattern / Files / Verification / three diff-specific questions. Split the rest: **Findings** = discrete defects *introduced in this diff* that the author would fix if they knew (actionable, path-cited). **Human callouts** (informational, do not change a looks-good path, do not auto-implement): migration; new or changed dependency/lockfile; auth/permissions; breaking public contract; irreversible/destructive. Optional one-word verdict: `looks-good` | `needs-attention`. Do not add P0–P3 (premortem already L/M/H). Do not paste the Codex/Pi fail-fast rubric. Same-session self-review is **not** L2 `loop-verifier` identity split — do not claim independence. Reviewer does not start a fix queue in the same turn; Stop.

Composite skill + diet + adapter prose are shipped. Do not add a sixth skill or a skill OS.

## Shipped

- `skills/implementation/` (~39 lines), profiles `standard` / `enterprise-fullstack` four names, adapters “one best matching skill … usually `implementation`; add at most one specialist.”
- Calorie + composite unit tests assert 4, not 6.
- `staged-execution` points at `implementation` and “do not expect a third matching skill.”

## Residual (still open)

Public docs and examples still describe the **pre-1.5.0** six-skill list (`README.md`, `docs/profiles.md`, `docs/architecture.md` “at most two matching skills”, `examples/*.agent-layer.json`). `docs/profiles.md` “extra skills” is a **phantom** `install.ps1 -Skills`.

Default install does **not** copy `premortem` or `repo-grounded-change`. `implementation` tells the model to follow those contracts; named user load fails unless `skill-lifecycle` (not in INSTALL.md). Either inline the premortem output contract enough to stand alone, or document how to add the standalone packages — do not claim named load works on a stock standard install.

Description diet (section 2b) **not shipped**. `implementation` / `repo-grounded-change` / `staged-execution` still share “non-trivial implementation.” `git-safety` still “mentions git.” `research-audit` still analyze/audit/evaluate.

---

Historical problem (fixed in adapters, not in descriptions):

Adapters used to say: “Load at most two matching skills … unless the user explicitly names a skill.”

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

This is **not** a context-graph engine (Graphify/Graft/CodeGraphContext), skill OS, or token compressor. Sibling paths in the repo remain the grounding unit; do not add `graphify-out/` as a layer artifact.

### 2b. Description diet (OpenAI Astra skills blog)

A matching budget of “one best skill” fails if five `description:` lines all match the same task. Codex then **truncates** descriptions to fit, so matching gets worse as the catalog grows. That is the pack/default-diet problem, not a reason to write a skill OS.

Keepable authoring rules (layer source + `docs/skill-authoring.md`):

1. **Short, narrow `description`.** One line: what it does + when it fires. Not a topic dump. OpenAI’s own contrast: bad “use when working with databases, queries, models, or persistence”; good “use when adding or changing a migration, or reviewing its rollout.”
2. **Body is a contract, not an itinerary.** When / Success / Boundaries / Evidence / Output / Stop. Progressive disclosure: fat pack skills may point at `references/` instead of pasting recipes (same as “composite shorter than the sum”). Do not split tiny skills into five files just to look like a router. Do **not** add OpenViking-style `.abstract.md` / `.overview.md` beside every `SKILL.md` — frontmatter `description` is the L0 trigger; the contract body is L2; When/Success is L1 in the same file.
3. **Model-neutral.** Overlay skills ship to Codex, Claude, Copilot, Gemini, Cursor. Do **not** strip Evidence/Stop because “Astra already tests.” Do **not** add Sol-era “read architecture.md before every edit.” inherit-current stays.

Live over-broad descriptions in this repo (fix in this WP, do not wait for a 0010): `backend-api`, `design-system`, `frontend-engineering`, `data-quality`, `security-hardening`, `research-audit` (fires on analyze/audit/evaluate), `git-safety` (“mentions git” fires on every commit). `implementation` / `repo-grounded-change` / `staged-execution` currently share “non-trivial implementation” — after the composite, the two standalones must say **explicit user load / named only**, not the same trigger.

Reject from the blog: `$skill-creator` as a layer skill; Astra-only description wording; counting “tokens saved.” Live anti-pattern: context-mode’s `description` fires on logs, JSON, Playwright, tests, git, docker, CI, security, “ANY MCP tool output that may exceed 20 lines” — that is a topic dump, not a trigger (do not copy).

### 2c. Minimal-diff ladder (Ponytail harvest, no new skill)

[Ponytail](https://github.com/DietrichGebert/ponytail) is a slogan plugin: YAGNI ladder, hooks, `lite|full|ultra`, “use on ANY coding task.” Do **not** install it, copy `AGENTS.md` to 20 hosts, or add a sixth core skill. Their own control: a bare “YAGNI + one-liners” prompt **dropped a safety guard**; terse-prose (“caveman”) did not shrink code.

Keepable **inside** `implementation` / `repo-grounded-change` (after the sibling-pattern step, not in always-on adapters):

1. Prefer, in order: existing helper in this repo → stdlib/language feature → native platform (HTML/CSS/DB constraint) → **already-installed** dependency → then the smallest new code. New packages still **Stop** for confirmation.
2. Never omit trust-boundary validation, data-loss handling, auth/secrets, accessibility the user asked for, or **named repo checks** to make the diff shorter. Short because necessary, not golfed.
3. Bugfix: grep callers of the function you touch; prefer one root-cause guard on the shared path over N symptom patches. Smallest wrong-place diff is a second bug.
4. No unsolicited abstraction / “for later” scaffolding (already: no drive-by, no extra framework). Extra the user did not ask for: skip it, one line in the review packet, do not stall the authorized work (0007).

Sibling patterns and `DECISIONS.md` / `skills-local` still beat “native `<input type=date>`” when this repo already has a DatePicker. That is why the ladder is **not** always-on and **not** a pack that fights `design-system`.

Reject from Ponytail: SessionStart hooks; intensity OS; `ACTIVE EVERY RESPONSE`; “code first, at most three lines” (fights the review packet); invented `ponytail:` comments; inventing a `test_*.py` instead of the repo’s named checks; `~/.codex/AGENTS.md`; MCP.

### 3. Risk-tiered use (with 0005)

Trivial work: do not load `implementation`’s premortem branch; git-safety + permissions suffice. Medium/high: `implementation` including premortem. Doctor still 0005 (unknown-trust only).

## Implementation

1. Add `skills/implementation/` contract-shaped SKILL.md: When to Use / Success Criteria / Boundaries / Evidence / Output / Stop. Point to sibling skill names instead of pasting three documents in full — keep the composite **shorter than the sum** (target ≤80 lines of SKILL.md).
2. `skill.json` like other core skills; `analyze-target.ps1` default skill lists; `profiles/standard.json` and `enterprise-fullstack.json`; overlay-calorie test **now** asserts four names including `implementation` — keep that; do not revert to six.
3. Six adapters: matching-budget wording; calorie test still ≤80 always-on.
4. `staged-execution` Strategy bullet: “default implementation path is the `implementation` skill; do not also load repo-grounded-change and premortem unless the user named them.”
5. Changelog + `changes/` declaration if profiles are contract-sensitive.
6. `docs/skill-authoring.md`: description = short + narrow when; no topic-keyword lists; body stays contract-shaped; references only for substantial domain detail. Rewrite the over-broad pack/core `description:` lines listed above in the same WP (calorie-neutral: frontmatter only). Optional cheap test: default-profile skill descriptions must not share the same “Use for non-trivial implementation” trigger.

Do not:

- Fold `frontend-engineering`, `precision-domain`, `database-engineering` into `implementation`.
- Delete the three standalone skills.
- Add a runtime skill loader or “2 vs N” enforcer.
- Add a `ponytail` / YAGNI slogan skill or always-on ladder in adapters.
- Absorb Ruflo/Claude-Flow agent catalogs, SPARC phase skills, or `npx ruflo init` (100+ agents is the opposite of a four-name diet).
- Paste Abdo’s Plus-quota user prompt into adapters or `AGENTS.md` (calorie, host billing, arbitrary “10 tests”). The keepable is one Stop line in this skill.
- Add `wait-what` / concision / ASD-STE100 / `CONTEXT.md` as a catalog or matching skill. Re-pitch is human-invoked ([0007](0007-portable-execution-tiers.md)); `description:` must not match “confused / explain / wait.” Target files before edit stay in this skill + `staged-execution`, not a slash command.
- Add `pi-review` / `/review` / `REVIEW_GUIDELINES.md` / P0–P3 / Codex `review_prompt.md` as a catalog skill. The keepable is the Findings vs Human-callouts split in this skill’s Output. Independent review stays L2 `loop-verifier`.

## Premortem

- A fat composite that pastes three SKILL.md files undoes the diet. Cap length; reference, don’t clone.
- Leaving all six defaults **plus** `implementation` makes matching worse. Replace, don’t append.
- “≤120 lines matching budget” in adapters can rot like “two skills”. Calorie CI measures always-on, not matching. Accept that, or add a cheap test that the `implementation` SKILL.md itself is ≤80 lines.
- inherit-current remains one model for plan/simulate/review. The composite does not create an independent verifier. That stays an L2/loop concern (feedback item 2 — not this WP). `pi-review`’s “empty branch” is host session-tree, not overlay independence.
- A Human-callouts list that also auto-queues fixes recreates `/end-review` “return and fix.” Callouts must not become the implementation checklist.
- Narrowing `git-safety` so it never matches would hide the default safety skill. Keep a **git-mutation** trigger (commit/push/merge/rebase/tag), drop “mentions git.”
- Astra-optimizing descriptions (“the model already knows”) makes Copilot/Gemini skip Evidence. Keep the contract.

## Done when

- Default standard install lists four core skills including `implementation`, not six overlapping ones. **(shipped)**
- Adapters no longer say a hard “two” that contradicts the workflow. **(shipped)**
- README / profiles / architecture / examples match the four-name diet (no “six core skills”, no “at most two matching skills”).
- Pack slogan skills remain opt-in and outside the composite.
- Always-on calorie still ≤80.
- `implementation` Stop reports after two identical named-check FAILs; it does not invent tests or encode a numeric test cap.
- Review packet splits Findings (diff-introduced defects) from Human callouts (migration/dep/auth/breaking/destructive); callouts do not auto-fix and do not add a `/review` skill.
- Default-diet and pack `description:` lines no longer share one another’s triggers; `implementation` is the only default “non-trivial implementation” match; standalones are named-only.
- Stock standard install either inlines enough premortem for medium/high **or** documents a real named-load path (lifecycle), not a phantom `-Skills`.
