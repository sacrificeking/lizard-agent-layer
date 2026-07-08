# Quality Registry

The quality registry turns lizard-agent-layer from a collection of files into a measurable operating layer.

It scores skills, adapters, and profiles, records risk signals, and writes JSON plus Markdown reports under `.tmp/quality/`.

## Why it exists

The benchmark repos showed that high-quality agent infrastructure needs more than install scripts. It needs local evidence that every reusable artifact is clear, safe, portable, and appropriate for its risk level.

The registry is intentionally local-first. It does not crawl external repos and does not mutate target projects.

## Artifacts

- `registry/quality-rubric.json`: scoring dimensions and default minimum score.
- `registry/risk-signals.json`: configurable risk patterns and severities.
- `scripts/score-layer.ps1`: local scorer and report generator.
- `.tmp/quality/layer-quality-report.json`: machine-readable report.
- `.tmp/quality/layer-quality-report.md`: human-readable report.

## Scored objects

### Skills

Skills are scored for metadata, activation clarity, procedure quality, verification language, safety discipline, supporting material, and portability.

### Adapters

Adapters are scored for manifest completeness, safety guidance, memory startup discipline, handoff awareness, verification guidance, and portable destination conventions.

### Profiles

Profiles are scored for operating envelope, curated skill coverage, harness coverage, model role mapping, risk-adjusted verification, and adaptation notes.

## Risk labels

Risk labels are not bugs by themselves. They surface places where an artifact mentions sensitive behavior such as remote git operations, secrets, database migrations, destructive filesystem actions, or external network access.

Critical risk signals fail the strict gate. High and medium signals stay visible in the report so reviewers can decide whether the artifact has enough safeguards.

## Commands

Run the scorer locally:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\score-layer.ps1
```

Run it as a strict gate:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\score-layer.ps1 -Strict
```

Use a stricter threshold for hardening work:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\score-layer.ps1 -Strict -MinScore 80
```

## Maturity path

The current gate enforces baseline quality. Future versions should add deeper maturity levels:

- `baseline`: valid, safe, and installable.
- `ready`: clear activation, workflow, and verification.
- `hardened`: includes references, examples, scripts, or tests.
- `certified`: has scenario tests, drift checks, and target-specific evidence.
