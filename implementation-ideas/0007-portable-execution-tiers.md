# 0007 — Portable fast vs rigorous execution tiers

**Work package:** fold the two-tier *behavior* into 0005/0006 and `USING.md`. Do **not** ship a layer-owned `.agents/rules/execution-mode.md`.
**Source:** live Codex/Antigravity customization in a target: `.agents/rules/execution-mode.md`, hidden via `.git/info/exclude`.
**Related:** [0005](0005-windows-operator-happy-path.md) risk-tiered doctor; [0006](0006-implementation-skill-and-matching-budget.md) composite skill.
**Also:** Khazix Astra `AGENTS.md` (X 2096125440893329685) — personal global card, not a product. Keepable lines below; do not copy the Chinese file.
**Also:** OpenAI model guides GPT-4.1 → GPT-6 Astra (https://developers.openai.com/api/docs/guides/latest-model?model=gpt-6-astra) plus Codex `AGENTS.md` discovery. Merge keepable adapter lines here; do not file a Codex-only idea.
**Also:** OpenAI “Rethinking skills and prompts for GPT-6 Astra” (https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra) — AGENTS.md required-reading and persistence/Stop; skill *descriptions* belong in [0006](0006-implementation-skill-and-matching-budget.md).
**Also:** Abdo GPT-6 Astra Plus 1%/6% quota videos (https://x.com/abdobuild/status/2098161708510429333, https://x.com/abdobuild/status/2098582463261856164). Reject as overlay (table below). FAIL-twice Stop belongs in [0006](0006-implementation-skill-and-matching-budget.md) `implementation` skill, not always-on adapters.
**Also:** Vox / Matt Pocock `wait-what` (https://x.com/Voxyz_ai/status/2098788729087295795, https://github.com/mattpocock/skills/tree/3cca18b368ae95cdbdebbff572ccafa662551015/skills/productivity/wait-what). Reject as a layer skill (table below). Optional USING one-liner is keepable, **not** this Remaining WP.
**Also:** Earendil `pi-review` (https://github.com/earendil-works/pi-review) and sibling `pi-review-loop`. Reject as overlay (table below). Findings vs Human callouts land in [0006](0006-implementation-skill-and-matching-budget.md) skill Output; adapter residual-risk kinds stay this Remaining WP.

**Status (2026-09-16):** **Shipped** (wp15). USING Fast/Rigorous shipped in 1.5.1; Adapter Output diet (residual risks conditioned on gates or high-risk changes), Stop rules, and Cursor MDC documentation shipped in wp15.

**Completed in wp15:** Six adapters received calorie-neutral task contract output diet (residual risks only on gates or migration / new-or-changed dependency / auth / breaking contract / destructive; pause/diverge cites path + line; diff-scaled evidence). Cursor MDC documented as opt-in (`alwaysApply: false`). Reject tables below remain binding.

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
| Spec Kit slash OS (`/speckit.constitution` → specify → clarify → plan → tasks → implement → converge) | Adjacent product ([architecture.md](../docs/architecture.md)). Tweet X 2097955506891469272 is only a recap. Constitution-as-always-on fights calorie and 0007 Tier 1. “Spec is source of truth, code is regenerated” fights repo-grounded change and ADR 0008. Their own dogfood: small fixes skip the pipeline — that is already Tier 1. `specify init` writing `.claude/commands/` / `.specify/` is a second overlay; do not merge, do not install. WHAT-before-HOW and “don’t guess, mark gaps” are already staged-execution + harvest `unverified`. |
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

### Keepable from Khazix Astra `AGENTS.md` (merge here, no new idea)

That file is a short global Codex card: lead with conclusion, user beats skills/memory, keep going until the goal, scale tests, one canonical rule body, CLAUDE.md as shim. Most of it is already `prompt-trust.md`, sidecar adapters, and this tier split.

Three lines are not yet explicit in 0005/0006 and belong on **Tier 1**:

1. **Do not invent gates.** No extra warnings, disclaimers, approval rituals, or security checklists for *imagined* risk. Real `permissions.md` never-allowed still applies. Adapter **Output** today always asks for “residual risks” — on trivial edits that becomes theater (same class as SHA parrot). Change to: residual risks only if a gate fired or the change is medium/high.
2. **Scale verification.** Do not add tests that only restate a reversible one-line change. Run the repo’s named checks that match the diff; if they pass, do not expand or repeat unless the diff, a failure, or an open doubt changed. Aligns with “typo = no premortem.”
3. **One rule body.** Harness files stay shims (already). Do not copy `permissions.md` / prompt-trust into every adapter. Khazix “CLAUDE.md is compatibility entry only” is the sidecar model — keep it; do not add a second prose copy.

Reject from that card: default Simplified Chinese; `rg`-only (Windows hosts); Feishu/Chrome-console tools; sub-agent OS; “never add approval because of hypothetical risk” if that would skip paste-stop or production/deploy gates.

### Keepable from OpenAI GPT-4.1 → GPT-6 Astra (merge here, no new idea)

Official Astra prompting is a **Codex/API harness guide**, not an overlay product. Most of the 4.1→6 lineage is already this file, [0006](0006-implementation-skill-and-matching-budget.md), [0009](0009-instruction-debt-audit.md), `prompt-trust.md`, and ADR 0004/0008/0009. Three portable lines are not yet explicit:

1. **Cite the blocking instruction.** Astra: if a skill / `AGENTS.md` / protocol causes a pause, confirmation, unfinished work, or a turn away from the user request, name the file, quote the line, and say whether that line is an explicit requirement or an interpretation. If no such line exists, that is an invented gate (item 1 above) — do not pause. Runtime counterpart of 0009; calorie-neutral **Output** on pause only, not on every typo.
2. **User beats skill guidelines, not `permissions.md`.** Astra “user instructions take precedence over a skill” is already prompt-trust item 3. Spell the exception in adapters: chat/user may skip overlay *skill* ceremony (Tier 1, extra specialist, USING). Chat may **not** waive never-allowed, paste-stop, or overlay plan SHA. Do not paste Astra’s “you don’t need user permission for reversible tasks” as a blanket waiver.
3. **Always-on prefix stays byte-stable.** Astra/Codex prompt cache and `configuration_update` assume a stable instruction prefix. Adapter files stay static templates: no install-time version, date, plan SHA, model id, or `gpt-6-astra`. Effort and model remain `inherit-current` (ADR 0009). Surgical host edits (Codex `apply_patch`, Cursor/Claude search-replace) stay **host-native** — do not paste V4A/`apply_patch` format into overlay skills.

**Authorized work before questions** maps to the existing tiers, not a new prompt: Tier 1 does the reversible edit; Tier 2’s reviewable result is the plan/premortem, not “should I start?”. Overlay mutations still plan-then-apply.

From the same Astra **skills/prompts** blog (not a new idea):

4. **No required-reading stack in always-on.** “Before every edit, read architecture.md, database.md, and deployment.md” is the doctor-every-turn failure. Adapters may *point* at docs by task kind (schema → database.md) the way USING is ask-only. Do not grow AGENTS.md into a pre-read list.
5. **Completion lives in Stop / the user request**, not an always-on “keep going.” The blog’s persistence note is why Tier-2 skills already have Stop; do not add GPT-4.1 keep-going to adapters. “Local tests use disposable fixtures — run and fix without asking at each step” is Tier-1 **Evidence**, not a `permissions.md` waiver.

### Keepable from wait-what (not remaining WP)

Matt Pocock `wait-what` is three lines: human-invoked re-pitch in plain register, using project nouns from `CONTEXT.md`. That is the design, not a stub. Skills that fight verbosity fail by growing.

Portable slice, already lizard-shaped:

- Only the **listener** knows they were lost. Codex `allow_implicit_invocation: false` / Claude `disable-model-invocation: true` — the agent must not auto-load it. Overlay equivalent: do **not** make a matching skill whose `description:` fires on “confused / explain / wait.”
- Name the listener (“I did not follow”), not the output (“be concise”). “Be brief” becomes telegrams; the missing premise stays missing.
- Reuse nouns we already have: `DECISIONS.md` / harvest terms, not a new `CONTEXT.md` / `CONTEXT-MAP.md`.
- Plan-side files are already `staged-execution` (“clarify target files … before editing”). After-change files are already `implementation` Output. Catman’s “which files will change” is those contracts, not a slash command.

Optional rider, **not** this Remaining WP (USING Fast/Rigorous is shipped; do not append a chapter): one Daily-Prompts / Review line in `templates/operator-card.md` — if you did not follow, say so and ask it to re-state the files it will change, using DECISIONS nouns, including the premise you were missing. Do not ask only for shorter. Can ride with [0010](0010-correction-routing-not-company-brain.md)’s USING bullet. Do not install `/wait-what`, ASD-STE100, or `grill-with-docs`.

Reject from those docs (do not reopen as a new idea):

| Vendor line | Why it stays out |
| --- | --- |
| GPT-4.1 “keep going until solved / do not stop at a plan” as always-on | Fights staged-execution, install plan SHA, ADR 0008 no auto-merge |
| Astra “do not introduce approval flows due to hypothetical risk” as blanket | Same failure as Khazix: would skip paste-stop and production/deploy |
| Subagent “always parallelize” / Codex subagent OS | Adapter already `nativeDelegation: true`; layer is not an orchestrator |
| Async tools, mid-turn steering, Responses `configuration_update` | API harness. Overlay does not own the Codex event loop |
| Compaction items / Codex notes across context windows | Host memory. Do not add a second notes OS beside `memory-policy` |
| Layer-managed `~/.codex/AGENTS.md` or `AGENTS.override.md` | Machine-global, Graft-shaped. 0009 already: report-only if the human asks |
| Codex `project_doc_max_bytes` (32 KiB) as a layer quota | Reason to keep adapters as shims (already). Not a new CI gate |
| OpenAI Docs skill `$openai-docs migrate … to GPT-6 Astra` | API consumer skill. Overlay is not an OpenAI SDK app |
| Personality / “slop words” lists in adapters | Calorie and tone. Contract-shaped Output already |
| Pin `gpt-6-astra`, effort, Fast mode, 272K cache cliff | ADR 0009 inherit-current; billing is API logging (zodchiii, not filed) |
| Abdo Astra Plus 1%/6% weekly-quota prompt; “don’t run more than 10 tests” (X 2098161708510429333 / 2098582463261856164) | ChatGPT Plus weekly usage is **host billing**. Overlay cannot throttle Astra. “10 tests” is an arbitrary user-turn constraint; Markdown cannot enforce it; a real named CI suite can exceed 10. Quota % is unverified anecdote (same class as Anshu). Scope-lock and “only needed context” are already 0006 matching + this file’s no required-reading stack + `context-hygiene`. FAIL-twice Stop is [0006](0006-implementation-skill-and-matching-budget.md) Remaining WP item 4 (`implementation` skill), already in `minimal-fix` / loop `max_attempts_per_item`. Do not paste the tweet into adapters. |
| Anshu Luna-orchestrator + Astra-coder Plus-quota recipe (X 2098014776886448337) | Host model picker. Portable default is inherit-current (ADR 0009). `loop-budget` may say cheap vs strong **roles**, never Luna/Astra names. Fresh-context / “stop after implementation” is already Stop + context-hygiene, not a subagent OS. Quota math was revised in-thread (80–90% → 40–70%); do not encode unverified savings. |
| context-mode (mksglu/context-mode): MCP sandbox, FTS5 session DB, PreToolUse hooks, 17-platform `AGENTS.md` copies, `~/.codex` global | Adjacent **runtime** (Graft/Spec-Kit class), Elastic-2.0, not MIT overlay. Hooks + `ctx_*` tools are a second product; Markdown cannot enforce them (architecture). Routing file is always-on calorie and Codex-shaped. Session SQLite is a second memory OS beside `memory-policy`. Blocking shell/`curl` fights named-test **Evidence** (visible output, not FTS hits). Skill `description` is a topic dump (0006). Windows sandbox CWD is temp — fights 0005. Portable slice already in `context-hygiene.md`: summarize large tool output, keep a path/hash to the evidence; do not hide PASS. Their later “no prose-style enforcement” confirms we do not add slop-word lists. 0009: if a target has the plugin, list it as a second overlay; do not merge. |
| OpenViking (volcengine/OpenViking): `viking://` context DB, L0/L1/L2 files, session→LLM memory extract, `soul.md`/`identity.md`, MCP+hooks, AGPLv3 | Adjacent **context database** (HQ + Graft + context-mode). Overlay already has Resource≈repo, Memory≈`DECISIONS`/`LESSONS`/`PREFERENCES`, Skill≈`SKILL.md`. Progressive load is 0006 description+body, not extra `.abstract.md` per skill. Auto-extract on session commit fights 0010 (harvest stops for human). `soul`/`identity` are personality always-on (slop). Vector RAG / knowledge graph is not a layer contract. AGPL cannot be vendored into MIT. Volcengine SaaS is not a dependency. 0009: if `openviking` MCP/plugin is present, list as second overlay; do not merge. |
| Ponytail plugin (DietrichGebert/ponytail): always-on YAGNI ladder, hooks, `lite\|full\|ultra`, “ANY coding task” | Slogan skill, not a layer. Ladder **behavior** (reuse / stdlib / no new dep / don’t golf safety) belongs in 0006 `implementation` after sibling grounding. Always-on `AGENTS.md` + SessionStart fights calorie, Tier 1, and opt-in packs (`design-system`). Bare “one-liners” dropped a safety guard in their benchmark — do not copy that prompt into adapters. |
| Ruflo / Claude-Flow (ruvnet/ruflo): `npx ruflo init`, 100+ agents, 314 MCP tools, SPARC swarm, HNSW memory, Haiku/Sonnet routing | Adjacent **meta-harness**. Writes `.claude/` + `CLAUDE.md` into the target. SPARC 5-phase + spawned researcher/planner/architect is Spec-Kit + subagent OS; overlay already has 10-80-10 in one `implementation` skill. Model names in agents violate ADR 0009. Vector DB / federation / 35-plugin marketplace is Graft/OpenViking class. Silent hook routing is the instruction-debt failure 0009 exists to catch. 0006: do not absorb the catalog. Quality-gate-before-next-phase is already Stop + premortem, not five agents. |
| Graphify (Graphify-Labs/graphify): tree-sitter code graph, `/graphify`, `graphify-out/`, always-on `AGENTS.md` “read GRAPH_REPORT.md first”, MCP/Neo4j | Adjacent **code-graph engine** (Graft/CodeGraphContext class). Do not reopen. Overlay grounding is 1–3 sibling **paths** in the repo, not a second index. `graphify install --platform codex` writes always-on graph guidance into `AGENTS.md` — required-reading stack and sidecar clash. EXTRACTED vs INFERRED is already harvest `unverified` / path-cite, not a reason to ship AST+wiki. SHA cache ≠ overlay manifest. 0009: if `graphify-out/` or `$graphify` is present, list as second overlay; do not merge. |
| wait-what skill / `/wait-what` (mattpocock/skills `productivity/wait-what`; X 2098788729087295795) | Slogan skill + slash OS (Spec Kit class). Three-line body is the lesson, not a reason to add a fifth core skill. `CONTEXT.md` / `CONTEXT-MAP.md` is a second glossary beside `DECISIONS.md`. ASD-STE100 in overlay is personality/register (slop-word class). `grill-with-docs` / domain-modeling / `ask-matt` are catalog OS. Host `disable-model-invocation` is not a portable layer contract. 0009: if a target has `wait-what` or `CONTEXT.md` as a second overlay, list it; do not merge. |
| pi-review (`earendil-works/pi-review`) + pi-review-loop | **Pi host extension**, not a portable skill. `/review` `/end-review` slash OS (Spec Kit class). `gh pr checkout` mutates the worktree (Pi’s own AGENTS.md forbids that unless the user asks; lizard has no GitHub client, ADR 0008). Fresh-session / empty-branch is Pi session-tree. `REVIEW_GUIDELINES.md` next to `.pi` is a second always-on rubric. Codex `review_prompt.md` port (fail-fast, SQL, open-redirect) is stack opinion + `security-hardening` pack, not adapters. P0–P3 is a second severity ontology beside premortem L/M/H. Auto “return and fix” is implementer=reviewer in one agent. pi-review-loop is a persistent UI + session checkpoint runtime (Graft class). Keepable: Findings vs Human callouts in [0006](0006-implementation-skill-and-matching-budget.md); adapter residual-risk *kinds* in this Remaining WP. 0009: if `.pi/` + `REVIEW_GUIDELINES.md` or `/review` is present, list as second overlay; do not merge. |

## Implementation (only if 0005/0006 are in flight or done)

Do not add a seventh always-on protocol file.

1. `skills/implementation/SKILL.md` (0006): explicit **When to Use / When to skip** matching Tier 1 vs 2. Skip = typo, unused import, padding/color/icon/copy, local test-name tweak. Full path = money/precision math, DB/RLS, auth/secrets, new packages, CI, wide refactors.
2. `templates/operator-card.md`: 4–6 lines, two bullets. No DCA/Supabase/Tailwind names in the layer template.
3. Six adapters: calorie-neutral replace, don’t append:
   - trivial → no extra skills;
   - otherwise load `implementation`;
   - **Output:** residual risks only when a permission gate fired or the change is migration / new-or-changed dependency / auth / breaking contract / destructive — not on every typo; informational, not a fix queue;
   - **Pause/diverge:** if you stop, ask, or leave work unfinished because of overlay text, cite `path` + quoted line; if you cannot quote it, continue (invented gate);
   - **Evidence:** named repo checks proportional to the diff; no extra tests that only restate the change; no repeat run after PASS unless the diff or a failure changed.
   Keep ≤80 always-on lines. Do not inject version/date/SHA/model into the adapter body.
4. `docs/skill-authoring.md`: example of a **committed** `skills-local` execution-tier list for stack-specific fast paths. State that `.git/info/exclude` is not an integrity control.
5. No installer path under `.agents/rules/`. No new pack. Overlay calorie tests still pass.

0006 **is** implemented. Do not use the staged-execution-only fallback.

## Residual (still open)

1. All six adapters Task Contract **Output:** still “Report … residual risks.” Change to: residual risks only if a permission gate fired or the change is migration / new-or-changed dependency / auth / breaking contract / destructive (Human callouts; informational; not a fix queue). Calorie-neutral replace.
2. Pause/diverge cite (`path` + quoted line) not in adapters.
3. Evidence scale (no extra tests that only restate a one-line change) not in adapters.
4. **Cursor:** `alwaysApply: false` and no globs — calorie **locks** that. `docs/getting-started.md` says “Cursor rules should always apply.” Either set always-on honestly (and update the calorie test) **or** fix the doc. Do not leave the contradiction. Prefer: document that Cursor must enable the lizard rule (not silently weaker than Codex).
5. USING already has Fast vs Rigorous — do not append a second USING chapter.

## Premortem

- Shipping `.agents/rules/execution-mode.md` as managed would pass doctor on Codex and **never load** on Copilot/Cursor unless adapters duplicate it — calorie and ADR 0004 fail.
- Hiding the rule in `exclude` makes “0 WARNINGS” a lie: the model’s real standing instruction is unreviewed.
- Putting Tailwind/Supabase/DCA into the **layer** template re-brands the overlay as one app’s stack.
- Fast path that also skips `permissions.md` (secrets in a “simple” UI change) is the failure mode. Fast path still obeys paste-stop and never-allowed.
- Copying Astra “do not stop at a plan / no hypothetical approvals” into always-on would un-teach staged-execution and plan SHA. Tiers already say when not to plan.
- “Cite the blocking instruction” on every completed typo recreates residual-risk theater. Cite **only** when the model actually paused, asked, or diverged.

## Done when

- Two-tier behavior is in USING.md. **(shipped)** Adapter Output/Evidence match it.
- Layer does not own `.agents/rules/`.
- Cursor always-on vs docs is one story, not two.
- Stack-specific fast-path lists, if any, are target-owned and committed.
- Always-on calorie unchanged.
- 0005 owns prompt-trust/doctor; 0006 owns load; this idea only specifies *when* the heavy path runs and how Output looks.
