# 0007 — Portable fast vs rigorous execution tiers

**Work package:** fold the two-tier *behavior* into 0005/0006 and `USING.md`. Do **not** ship a layer-owned `.agents/rules/execution-mode.md`.
**Source:** live Codex/Antigravity customization in a target: `.agents/rules/execution-mode.md`, hidden via `.git/info/exclude`.
**Related:** [0005](0005-windows-operator-happy-path.md) risk-tiered doctor; [0006](0006-implementation-skill-and-matching-budget.md) composite skill.

Do not change product files until this idea is explicitly approved for implementation.

## Verdict

**Take the behavior. Reject the mechanism as a lizard product.**

The two-stage split (trivial → no planning tax; finance/DB/auth/deps → plan + premortem + evidence) is the same operator need as 0005/0006. Encoding it as a **Codex-native rules file that is git-excluded** is not portable, not team-reviewable, and not a layer contract.

## What the live rule got right

- Small UI/typo/import work should not spawn plans, premortem, or doctor.
- Precision, migrations/RLS, auth/secrets, and dependency adds should run the full implementation contract.
- Doctor/manifest staying green is good **if** the file is not a managed layer artifact.

## What not to absorb

| Live choice | Why it stays out of the layer |
| --- | --- |
| Layer-owned `.agents/rules/execution-mode.md` | Codex/Antigravity path. Cursor uses `.cursor/rules`, Copilot uses `.github/`, Claude uses `CLAUDE.md`. ADR 0004: adapters translate **generic** `.agent/` core. A rules file in `.agents/` makes one harness the source of truth. |
| `.git/info/exclude` so git status stays clean | Local-only ignore. Safety posture then differs per machine. Bank/team clones never see the rule. Unmanaged text can contradict `AGENTS.md` while doctor still reports 0 drift (the file is invisible to the manifest). |
| Target-specific triggers (Tailwind, DCA/APY, Supabase) | Project domain. That belongs in **committed** `.agent/skills-local/` or `DECISIONS.md`, not in a generic pack and not in a hidden rules file. Same reason we do not ship an ING pack. |
| `implementation_plan.md` as a required artifact | Not a lizard object. Lizard plans are install/update/uninstall canonical JSON. Daily work should not invent a second SDD CLI. |
| “Automatically on for Gemini & Codex” as a layer claim | Host loaders are not ours. Adapters may *mention* optional host rules; they cannot promise Antigravity/Codex will load them. |

## Solution

Portable contract, already mostly specified:

1. **Tier 1 (fast)** — 0005 trivial path: `permissions.md` + `git-safety`. No doctor, no premortem, no pack skills, no confirmation of trivial lines. Adapter: skip integrity gate on routine edits in a trusted workspace (already sketched in current Codex adapter wording).
2. **Tier 2 (rigorous)** — 0006 `implementation` skill: plan → repo-grounded change → premortem on medium/high → named tests with visible output. Trigger on *kind of work*, not on a hidden rules file: migrations, auth, secrets, dependencies, precision/money math, CI, large refactors.
3. **USING.md** (one short section, human card): when to demand the fast vs rigorous path. Ask-only from adapters.
4. **Project-specific lists** (optional, target-owned, **committed**):
   - `.agent/skills-local/execution-tiers/SKILL.md` or a `DECISIONS.md` rule: “in *this* repo, Tailwind-only is Tier 1; `supabase/migrations` is Tier 2.”
   - Doctor already treats `skills-local` as user-owned.
   - Do not gitignore or `exclude` that file. Teams must review it.

If a harness *also* reads `.agents/rules/`, a human may copy the same text there. That copy is **not** installed, not hash-bound, not the overlay source of truth.

## Implementation (only if 0005/0006 are in flight or done)

Do not add a seventh always-on protocol file.

1. `skills/implementation/SKILL.md` (0006): explicit **When to Use / When to skip** matching Tier 1 vs 2. Skip = typo, unused import, padding/color/icon/copy, local test-name tweak. Full path = money/precision math, DB/RLS, auth/secrets, new packages, CI, wide refactors.
2. `templates/operator-card.md`: 4–6 lines, two bullets. No DCA/Supabase/Tailwind names in the layer template.
3. Six adapters: one clause, calorie-neutral (replace, don’t append): trivial → no extra skills; otherwise load `implementation`. Keep ≤80 always-on lines.
4. `docs/skill-authoring.md`: example of a **committed** `skills-local` execution-tier list for stack-specific fast paths. State that `.git/info/exclude` is not an integrity control.
5. No installer path under `.agents/rules/`. No new pack. Overlay calorie tests still pass.

If 0006 is not implemented yet, do steps 2–4 against `staged-execution` + `premortem` skip lists only (same text, no composite skill).

## Premortem

- Shipping `.agents/rules/execution-mode.md` as managed would pass doctor on Codex and **never load** on Copilot/Cursor unless adapters duplicate it — calorie and ADR 0004 fail.
- Hiding the rule in `exclude` makes “0 WARNINGS” a lie: the model’s real standing instruction is unreviewed.
- Putting Tailwind/Supabase/DCA into the **layer** template re-brands the overlay as one app’s stack.
- Fast path that also skips `permissions.md` (secrets in a “simple” UI change) is the failure mode. Fast path still obeys paste-stop and never-allowed.

## Done when

- Two-tier behavior is in the portable `implementation` (or staged-execution) contract and USING.md.
- Layer does not own `.agents/rules/`.
- Stack-specific fast-path lists, if any, are target-owned and committed.
- Always-on calorie unchanged.
- 0005/0006 remain the load and doctor WPs; this idea only specifies *when* the heavy path runs.
